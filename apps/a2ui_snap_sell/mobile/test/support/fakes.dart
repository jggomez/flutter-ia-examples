import 'dart:async';
import 'dart:typed_data';

import 'package:genui/genui.dart';
import 'package:mobile/domain/repositories/image_capture_repository.dart';
import 'package:mobile/domain/repositories/selling_agent_repository.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';

/// Deterministic in-memory fake for [ImageCaptureRepository] / [ImageCaptureService].
class FakeImageCaptureService implements ImageCaptureRepository {
  /// Pre-configured photo returned by the next [capturePhoto] call.
  CapturedPhoto? nextPhoto = CapturedPhoto(
    bytes: kFakeTransparentPng,
    mimeType: 'image/jpeg',
    fileName: 'test_item.jpg',
    source: PhotoCaptureSource.camera,
  );

  /// Optional exception thrown by [capturePhoto] when non-null.
  Object? nextError;

  /// History of sources passed to [capturePhoto].
  final List<PhotoCaptureSource> capturedSources = <PhotoCaptureSource>[];

  /// Queue of follow-up photos captured by `PhotoRequest` widgets.
  final List<CapturedPhoto> queuedFollowupPhotos = <CapturedPhoto>[];

  /// Last downscaling parameters passed to [capturePhoto].
  double? lastMaxWidth;
  double? lastMaxHeight;
  int? lastImageQuality;

  @override
  Future<CapturedPhoto?> capturePhoto(
    PhotoCaptureSource source, {
    double maxWidth = 1024,
    double maxHeight = 1024,
    int imageQuality = 82,
  }) async {
    capturedSources.add(source);
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastImageQuality = imageQuality;
    if (nextError != null) {
      throw nextError!;
    }
    return nextPhoto;
  }

  @override
  void queueFollowupPhoto(CapturedPhoto photo) {
    queuedFollowupPhotos.add(photo);
  }

  @override
  CapturedPhoto? takeQueuedFollowupPhoto() {
    if (queuedFollowupPhotos.isEmpty) return null;
    return queuedFollowupPhotos.removeAt(0);
  }
}

/// Deterministic in-memory fake for [SellingAgentRepository] / [A2uiAgentService].
class FakeA2uiAgentService implements SellingAgentRepository {
  /// Creates a [FakeA2uiAgentService] wired to a real [SurfaceController].
  FakeA2uiAgentService({ImageCaptureRepository? imageCaptureService})
    : _surfaceController = SurfaceController(
        catalogs: <Catalog>[
          buildSnapSellCatalog(imageCaptureService: imageCaptureService),
        ],
      );

  final SurfaceController _surfaceController;
  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();

  /// Recorded initial photos passed to [startSession].
  final List<CapturedPhoto> startedPhotos = <CapturedPhoto>[];

  /// Recorded initial prompts passed to [startSession].
  final List<String> startedPrompts = <String>[];

  /// Recorded action messages passed to [sendAction].
  final List<ChatMessage> sentActions = <ChatMessage>[];

  /// Recorded follow-up photos attached to [sendAction].
  final List<CapturedPhoto?> sentFollowupPhotos = <CapturedPhoto?>[];

  /// Optional canned A2UI v0.9 JSON messages emitted automatically on [startSession].
  List<Map<String, Object?>> cannedStartMessages =
      const <Map<String, Object?>>[];

  /// Optional canned A2UI v0.9 JSON messages emitted automatically on [sendAction].
  List<Map<String, Object?>> cannedActionMessages =
      const <Map<String, Object?>>[];

  /// Optional error thrown by [startSession] or [sendAction].
  Object? nextError;

  /// Optional custom handler for [sendAction].
  Future<String?> Function(
    ChatMessage interactionMessage,
    CapturedPhoto? followupPhoto,
  )?
  customSendAction;

  /// Number of times [dispose] has been called.
  int disposeCount = 0;
  bool _isDisposed = false;

  @override
  SurfaceController get surfaceController => _surfaceController;

  @override
  Stream<SurfaceUpdate> get surfaceUpdates => _surfaceController.surfaceUpdates;

  @override
  Stream<String> get textStream => _textController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  /// Feeds raw A2UI v0.9 JSON envelopes into [surfaceController].
  void emitJsonMessages(List<Map<String, Object?>> messages) {
    feedA2uiJson(_surfaceController, messages);
  }

  /// Emits conversational text on [textStream].
  void emitAgentText(String text) {
    if (!_textController.isClosed) {
      _textController.add(text);
    }
  }

  /// Emits an error on [errorStream].
  void emitError(Object error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  @override
  Future<String?> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  }) async {
    if (nextError != null) {
      throw nextError!;
    }
    startedPhotos.add(photo);
    startedPrompts.add(prompt);
    if (cannedStartMessages.isNotEmpty) {
      emitJsonMessages(cannedStartMessages);
    }
    return null;
  }

  @override
  Future<String?> sendAction(
    ChatMessage interactionMessage, {
    CapturedPhoto? followupPhoto,
  }) async {
    if (nextError != null) {
      throw nextError!;
    }
    sentActions.add(interactionMessage);
    sentFollowupPhotos.add(followupPhoto);
    if (customSendAction != null) {
      return customSendAction!(interactionMessage, followupPhoto);
    }
    if (cannedActionMessages.isNotEmpty) {
      emitJsonMessages(cannedActionMessages);
    }
    return null;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    disposeCount++;
    _textController.close();
    _errorController.close();
    _surfaceController.dispose();
  }
}

/// 1x1 transparent PNG bytes for deterministic widget tests.
final Uint8List kFakeTransparentPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
