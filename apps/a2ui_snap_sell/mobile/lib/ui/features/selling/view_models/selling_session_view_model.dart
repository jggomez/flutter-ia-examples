import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genui/genui.dart';

import '../../../../domain/repositories/image_capture_repository.dart';
import '../../../../domain/repositories/selling_agent_repository.dart';
import '../../../providers/repository_providers.dart';
import 'selling_session_state.dart';

/// Riverpod [Notifier] orchestrating the Snap & Sell session lifecycle.
class SellingSessionViewModel extends Notifier<SellingSessionState> {
  StreamSubscription<SurfaceUpdate>? _surfaceSub;
  StreamSubscription<ChatMessage>? _submitSub;
  StreamSubscription<String>? _textSub;
  StreamSubscription<Object>? _errorSub;
  Timer? _submittingTimeoutTimer;
  bool _isDisposed = false;

  late ImageCaptureRepository _imageCaptureRepository;
  late SellingAgentRepository _agentRepository;

  @override
  SellingSessionState build() {
    _isDisposed = false;
    _imageCaptureRepository = ref.watch(imageCaptureRepositoryProvider);
    _agentRepository = ref.watch(sellingAgentRepositoryProvider);

    _cancelSubscriptions();
    _cancelTimeoutTimer();
    _surfaceSub = _agentRepository.surfaceUpdates.listen(_onSurfaceUpdate);
    _submitSub = _agentRepository.surfaceController.onSubmit.listen(
      _onSurfaceSubmit,
    );
    _textSub = _agentRepository.textStream.listen(_onAgentText);
    _errorSub = _agentRepository.errorStream.listen(_onAgentError);

    ref.onDispose(() {
      _isDisposed = true;
      _cancelTimeoutTimer();
      _cancelSubscriptions();
      _agentRepository.dispose();
    });

    return const SellingSessionState();
  }

  void _cancelSubscriptions() {
    _surfaceSub?.cancel();
    _surfaceSub = null;
    _submitSub?.cancel();
    _submitSub = null;
    _textSub?.cancel();
    _textSub = null;
    _errorSub?.cancel();
    _errorSub = null;
  }

  void _cancelTimeoutTimer() {
    _submittingTimeoutTimer?.cancel();
    _submittingTimeoutTimer = null;
  }

  /// Captures an initial item photo from [source] and starts the A2UI selling wizard.
  Future<void> startSessionWithPhoto(PhotoCaptureSource source) async {
    if (_isDisposed || state.isProcessing) return;
    state = state.copyWith(
      status: SellingFlowStatus.capturingInitialPhoto,
      clearErrorMessage: true,
    );

    try {
      final CapturedPhoto? photo = await _imageCaptureRepository.capturePhoto(
        source,
      );
      if (_isDisposed) return;
      if (photo == null) {
        state = state.copyWith(status: SellingFlowStatus.idle);
        return;
      }

      final Map<String, Uint8List> updatedPhotos = <String, Uint8List>{
        ...state.localPhotos,
        'initial': photo.bytes,
        'local://initial': photo.bytes,
      };
      state = state.copyWith(
        status: SellingFlowStatus.analyzingItem,
        localPhotos: updatedPhotos,
        clearErrorMessage: true,
      );

      await _agentRepository.startSession(
        photo: photo,
        prompt: 'Analyze this item and start the selling wizard.',
      );
    } catch (error) {
      if (_isDisposed) return;
      state = state.copyWith(
        status: SellingFlowStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  void _onSurfaceUpdate(SurfaceUpdate update) {
    if (_isDisposed) return;
    switch (update) {
      case SurfaceAdded(:final String surfaceId):
      case ComponentsUpdated(:final String surfaceId):
        _cancelTimeoutTimer();
        final List<String> nextHistory = <String>[
          ...state.surfaceHistory.where((String id) => id != surfaceId),
          surfaceId,
        ];
        state = state.copyWith(
          status: SellingFlowStatus.activeSurface,
          activeSurfaceId: surfaceId,
          surfaceHistory: nextHistory,
          clearErrorMessage: true,
        );
      case SurfaceRemoved(:final String surfaceId):
        final List<String> remaining = state.surfaceHistory
            .where((String id) => id != surfaceId)
            .toList(growable: false);
        final String? fallbackSurfaceId = remaining.isNotEmpty
            ? remaining.last
            : null;
        state = state.copyWith(
          activeSurfaceId: fallbackSurfaceId,
          clearActiveSurfaceId: fallbackSurfaceId == null,
          surfaceHistory: remaining,
        );
    }
  }

  Future<void> _onSurfaceSubmit(ChatMessage message) async {
    if (_isDisposed || state.isProcessing) return;

    final String? actionName = _extractActionName(message);
    if (actionName == 'restart_flow' || actionName == 'retake_initial_photo') {
      resetSession();
      return;
    }

    final CapturedPhoto? followupPhoto = _imageCaptureRepository
        .takeQueuedFollowupPhoto();
    state = state.copyWith(
      status: SellingFlowStatus.submittingAction,
      clearErrorMessage: true,
    );

    _cancelTimeoutTimer();
    _submittingTimeoutTimer = Timer(const Duration(seconds: 25), () {
      if (_isDisposed) return;
      if (state.status == SellingFlowStatus.submittingAction) {
        state = state.copyWith(
          status: SellingFlowStatus.error,
          errorMessage: 'La solicitud tardó demasiado tiempo. Por favor intenta nuevamente.',
        );
      }
    });

    try {
      await _agentRepository.sendAction(message, followupPhoto: followupPhoto);
      if (_isDisposed) return;
      if (actionName == 'publish_listing' &&
          state.status == SellingFlowStatus.submittingAction) {
        _cancelTimeoutTimer();
        state = state.copyWith(status: SellingFlowStatus.published);
      }
      // state.status remains SellingFlowStatus.submittingAction until
      // a SurfaceUpdate arrives from the agent in _onSurfaceUpdate or timeout/error occurs.
    } catch (error) {
      _cancelTimeoutTimer();
      if (_isDisposed) return;
      state = state.copyWith(
        status: SellingFlowStatus.error,
        errorMessage: error.toString(),
      );
    }
  }

  String? _extractActionName(ChatMessage message) {
    final Iterable<UiInteractionPart> interactionParts =
        message.parts.uiInteractionParts;
    if (interactionParts.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(interactionParts.first.interaction);
      if (decoded is Map<String, Object?>) {
        final Object? action = decoded['action'];
        if (action is Map<String, Object?>) {
          return action['name'] as String?;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _onAgentText(String text) {
    if (_isDisposed) return;
    if (text.trim().isEmpty) return;
    state = state.copyWith(lastAgentText: text.trim());
  }

  void _onAgentError(Object error) {
    if (_isDisposed) return;
    _cancelTimeoutTimer();
    state = state.copyWith(
      status: SellingFlowStatus.error,
      errorMessage: error.toString(),
    );
  }

  /// Clears any error banner and returns to active surface or idle state.
  void clearError() {
    if (_isDisposed) return;
    _cancelTimeoutTimer();
    state = state.copyWith(
      status: state.activeSurfaceId != null
          ? SellingFlowStatus.activeSurface
          : SellingFlowStatus.idle,
      clearErrorMessage: true,
    );
  }

  /// Resets the selling session back to the initial entry screen.
  void resetSession() {
    if (_isDisposed) return;
    _cancelTimeoutTimer();
    for (final String surfaceId in List<String>.of(state.surfaceHistory)) {
      _agentRepository.surfaceController.registry.removeSurface(surfaceId);
    }
    state = const SellingSessionState();
  }
}

/// Alias matching prompt naming (`SellingSessionController`).
typedef SellingSessionController = SellingSessionViewModel;

/// Primary provider for [SellingSessionViewModel].
final NotifierProvider<SellingSessionViewModel, SellingSessionState>
sellingSessionViewModelProvider =
    NotifierProvider<SellingSessionViewModel, SellingSessionState>(
      SellingSessionViewModel.new,
    );

/// Alias matching prompt naming (`sellingSessionControllerProvider`).
final NotifierProvider<SellingSessionViewModel, SellingSessionState>
sellingSessionControllerProvider = sellingSessionViewModelProvider;
