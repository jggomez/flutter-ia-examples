import 'package:flutter/foundation.dart';

import '../../../../domain/models/selling_flow_status.dart';

export '../../../../domain/models/selling_flow_status.dart';

/// Immutable state for the Snap & Sell session.
@immutable
class SellingSessionState {
  /// Creates a [SellingSessionState].
  const SellingSessionState({
    this.status = SellingFlowStatus.idle,
    this.activeSurfaceId,
    this.surfaceHistory = const <String>[],
    this.localPhotos = const <String, Uint8List>{},
    this.lastAgentText,
    this.errorMessage,
  });

  /// Current lifecycle phase of the selling flow.
  final SellingFlowStatus status;

  /// Currently displayed A2UI surface ID, if any.
  final String? activeSurfaceId;

  /// Ordered history of active A2UI surface IDs.
  final List<String> surfaceHistory;

  /// Locally captured photo bytes keyed by identifier (e.g., `'initial'`, `'odometer'`).
  final Map<String, Uint8List> localPhotos;

  /// Latest conversational status text emitted by the remote agent.
  final String? lastAgentText;

  /// User-facing error message if the last operation failed.
  final String? errorMessage;

  /// Set view of active surface IDs.
  Set<String> get activeSurfaceIds => surfaceHistory.toSet();

  /// Whether the session is actively capturing or waiting on an agent turn.
  bool get isProcessing =>
      status == SellingFlowStatus.capturingInitialPhoto ||
      status == SellingFlowStatus.analyzingItem ||
      status == SellingFlowStatus.submittingAction;

  /// Creates a copy of this state with updated fields.
  SellingSessionState copyWith({
    SellingFlowStatus? status,
    String? activeSurfaceId,
    bool clearActiveSurfaceId = false,
    List<String>? surfaceHistory,
    Map<String, Uint8List>? localPhotos,
    String? lastAgentText,
    bool clearLastAgentText = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return SellingSessionState(
      status: status ?? this.status,
      activeSurfaceId: clearActiveSurfaceId
          ? null
          : (activeSurfaceId ?? this.activeSurfaceId),
      surfaceHistory: surfaceHistory ?? this.surfaceHistory,
      localPhotos: localPhotos ?? this.localPhotos,
      lastAgentText: clearLastAgentText
          ? null
          : (lastAgentText ?? this.lastAgentText),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
