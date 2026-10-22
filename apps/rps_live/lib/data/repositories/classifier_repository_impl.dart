// The two collaborators below are deliberately assigned manually (not via
// `this._cameraFrameService`/`this._classifierService`): a leading
// underscore in a named-constructor-parameter name makes it library-private,
// which would break `main.dart`'s (a different library) ability to pass
// these by name. `dart format` keeps rewrapping a trailing `// ignore:` on
// those initializer-list lines past 80 columns, so it's silenced file-wide
// instead of per-line.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart' show compute;

import '../../domain/models/classification_result.dart';
import '../../domain/models/raw_camera_frame.dart';
import '../../domain/repositories/classifier_repository.dart';
import '../../domain/use_cases/preprocess_frame_use_case.dart';
import '../services/camera_frame_service.dart';
import '../services/tflite_classifier_service.dart';

/// Composes [CameraFrameService] + [PreprocessFrameUseCase] +
/// [TfliteClassifierService] into the [ClassifierRepository] contract.
///
/// All three collaborators are injected via the constructor (not
/// looked up globally) specifically so tests can supply fakes for the
/// camera and the interpreter while exercising the real preprocessing math,
/// or fake all three to test game-logic/view-model code in isolation.
///
/// ## Isolate / throttling strategy
///
/// `package:camera`'s `startImageStream` delivers frames at the device's
/// native rate (commonly 30 fps), far more than the ~10-15 fps inference
/// target and far more than a 3-class classifier needs. Per frame:
///
/// 1. Frames are throttled to [minFrameInterval] — any frame arriving
///    before the interval has elapsed since the last *accepted* frame is
///    dropped immediately, before any processing.
/// 2. **[PreprocessFrameUseCase.call] runs on a background isolate**
///    (`compute`), since it does O(width*height) pixel work over the raw
///    camera buffer — the actual jank risk this pipeline has to avoid on
///    the UI isolate.
/// 3. **[TfliteClassifierService.classify] runs synchronously back on the
///    calling isolate.** This is a deliberate simplification: the
///    interface is intentionally synchronous (so simple fakes work in
///    tests with no `Future` plumbing), and a 96x96x1 single-channel,
///    3-class model's `Interpreter.run` call is expected to complete in
///    low-single-digit milliseconds — cheap enough not to reintroduce
///    jank at a 10-15 fps cadence. `TfliteClassifierServiceImpl` still asks
///    `InterpreterFactory` for platform acceleration (XNNPACK/GPU) to keep
///    that call fast. If on-device profiling (see the `flutter-implementer`
///    hand-off notes) shows this assumption is wrong for the real model,
///    the next step is a `flutter_litert` `IsolateInterpreter`, which needs
///    an async `classify()` — a breaking change to
///    `TfliteClassifierService` deliberately deferred until proven
///    necessary.
/// 4. A frame already in flight (steps 2-3) blocks acceptance of new frames
///    until it completes, so work never queues up unboundedly if a frame
///    takes longer than [minFrameInterval].
///
/// Any failure surfaced by the collaborators (missing model asset, camera
/// permission denial, mid-stream camera error) is forwarded as-is on
/// [classificationStream] — both [CameraFrameService] and
/// [TfliteClassifierService] implementations are contractually required to
/// only throw [ModelAssetNotFoundException]/[CameraUnavailableException]
/// (never a raw platform exception), so this repository does not need to
/// re-wrap anything itself.
class ClassifierRepositoryImpl implements ClassifierRepository {
  // Kept as manual assignments (not `this._cameraFrameService`/
  // `this._classifierService`): a leading underscore in a named-parameter
  // name makes it library-private, which would break `main.dart`'s (a
  // different library) ability to pass these by name.
  ClassifierRepositoryImpl({
    required CameraFrameService cameraFrameService,
    required TfliteClassifierService classifierService,
    this.preprocessFrameUseCase = const PreprocessFrameUseCase(),
    this.minFrameInterval = const Duration(milliseconds: 80), // ~12 fps
  }) : _cameraFrameService = cameraFrameService,
       _classifierService = classifierService;

  final CameraFrameService _cameraFrameService;
  final TfliteClassifierService _classifierService;
  final PreprocessFrameUseCase preprocessFrameUseCase;

  /// Minimum time between two *processed* frames; anything arriving sooner
  /// is dropped to hit the ~10-15 fps inference target without queueing.
  final Duration minFrameInterval;

  StreamController<ClassificationResult>? _outputController;
  StreamSubscription<RawCameraFrame>? _frameSubscription;
  bool _classifierLoaded = false;
  DateTime? _lastAcceptedFrameAt;
  bool _isProcessingFrame = false;

  /// Number of callers currently relying on this instance being
  /// initialized, reference-counted rather than a plain boolean.
  ///
  /// This repository is a single shared instance
  /// (`classifierRepositoryProvider.overrideWithValue(...)` in `main.dart`)
  /// consumed by both `VsAiViewModel` and `PracticeViewModel`, each of which
  /// calls [initialize]/[dispose] once per its own lifecycle. Since both are
  /// `.autoDispose` and `app.dart` mounts/unmounts screens via a plain
  /// indexed lookup, switching tabs makes the *incoming* screen's
  /// `initialize()` run (synchronously, as part of building the new
  /// widget) **before** the *outgoing* screen's `ref.onDispose` (and thus
  /// its `dispose()` call) actually fires — Riverpod schedules
  /// `autoDispose` teardown for a provider that lost its last listener via
  /// a microtask/zero-duration timer *after* the current widget tree
  /// rebuild finishes, not synchronously as part of it. A naive
  /// "unconditionally tear down, then rebuild" `initialize()`/`dispose()`
  /// pair would therefore let the outgoing screen's stale `dispose()` call
  /// tear down the incoming screen's brand-new camera/interpreter session
  /// moments after it started.
  ///
  /// Reference counting fixes this: an `initialize()` call while a session
  /// is already live just joins it (no redundant `load()`/`start()`, no
  /// interruption of the frames the other caller is already consuming from
  /// the shared broadcast [classificationStream]); the underlying
  /// camera/interpreter are only actually released once every caller that
  /// initialized has also disposed. This also makes both methods safe to
  /// call in any order / any number of times, including calling either one
  /// without a matching prior call (see [_teardown]'s doc comment).
  int _activeSessions = 0;

  @override
  Future<void> initialize() async {
    if (_activeSessions > 0) {
      // Already initialized (and healthy) for another caller: share the
      // already-running camera + loaded interpreter instead of tearing them
      // down and racing a fresh setup against whichever caller is still
      // using them.
      _activeSessions++;
      return;
    }
    _activeSessions = 1;
    try {
      // Idempotent-safety net: if this instance still has leftover internal
      // state from an earlier session that never received a matching
      // `dispose()` call (should not happen given the reference counting
      // above, but keeps `initialize()` safe to call regardless of prior
      // state, per the class's `dispose()` doc comment), clear it before
      // creating anything new. Guarded so a normal, clean `initialize()`
      // never issues a spurious extra `stop()`/`dispose()` call on the
      // collaborators.
      if (_frameSubscription != null ||
          _outputController != null ||
          _classifierLoaded) {
        await _teardown();
      }

      await _classifierService.load();
      _classifierLoaded = true;
      await _cameraFrameService.start();

      final outputController =
          StreamController<ClassificationResult>.broadcast();
      _outputController = outputController;
      _frameSubscription = _cameraFrameService.frames.listen(
        _onFrame,
        onError: outputController.addError,
      );
    } catch (_) {
      // Roll back so a future initialize() (from this caller retrying, or
      // from a different caller) starts from a clean slate rather than
      // being wedged in a "partially initialized, but counted as active"
      // state.
      _activeSessions = 0;
      await _teardown();
      rethrow;
    }
  }

  @override
  Stream<ClassificationResult> get classificationStream {
    final controller = _outputController;
    if (controller == null) {
      throw StateError(
        'ClassifierRepositoryImpl.initialize() must complete successfully '
        'before reading classificationStream.',
      );
    }
    return controller.stream;
  }

  void _onFrame(RawCameraFrame frame) {
    final now = DateTime.now();
    final lastAcceptedFrameAt = _lastAcceptedFrameAt;
    if (_isProcessingFrame ||
        (lastAcceptedFrameAt != null &&
            now.difference(lastAcceptedFrameAt) < minFrameInterval)) {
      return; // Drop: either still busy, or arrived too soon.
    }

    _lastAcceptedFrameAt = now;
    _isProcessingFrame = true;
    unawaited(_processFrame(frame));
  }

  Future<void> _processFrame(RawCameraFrame frame) async {
    final outputController = _outputController;
    try {
      final preprocessed = await compute(
        preprocessFrameUseCase.preprocessWithPreview,
        frame,
      );
      final raw = _classifierService.classify(preprocessed.normalizedInput);
      outputController?.add(
        ClassificationResult(
          paperConfidence: raw[0],
          rockConfidence: raw[1],
          scissorsConfidence: raw[2],
          previewPixels: preprocessed.previewPixels,
        ),
      );
    } catch (error, stackTrace) {
      outputController?.addError(error, stackTrace);
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  Future<void> switchCamera() => _cameraFrameService.switchCamera();

  @override
  Future<void> dispose() async {
    if (_activeSessions == 0) {
      // Already fully torn down (or never initialized) — safe no-op, per
      // the `ClassifierRepository.dispose()` contract ("safe to call
      // multiple times").
      return;
    }
    _activeSessions--;
    if (_activeSessions > 0) {
      // Another caller (see [_activeSessions]'s doc comment) is still
      // relying on the camera/interpreter staying up; only the last
      // `dispose()` actually releases them.
      return;
    }
    await _teardown();
  }

  /// Cancels the frame subscription, stops the camera and releases the
  /// interpreter, closing/nulling every field so a subsequent
  /// [initialize] starts from a clean slate. Safe to call when nothing (or
  /// only some) of that state exists.
  Future<void> _teardown() async {
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    await _cameraFrameService.stop();
    if (_classifierLoaded) {
      await _classifierService.dispose();
      _classifierLoaded = false;
    }
    final outputController = _outputController;
    _outputController = null;
    if (outputController != null && !outputController.isClosed) {
      await outputController.close();
    }
  }
}
