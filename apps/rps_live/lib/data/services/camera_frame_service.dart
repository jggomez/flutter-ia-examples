import 'dart:async';

import 'package:camera/camera.dart';

import '../../domain/models/raw_camera_frame.dart';
import '../../domain/repositories/classifier_repository.dart';

/// Thin wrapper around `package:camera` that exposes frames as
/// plugin-agnostic [RawCameraFrame]s.
///
/// Abstracted (rather than using `CameraController` directly inside
/// [ClassifierRepositoryImpl]) so tests can substitute a
/// `FakeCameraFrameService` that emits synthetic frames from a
/// `StreamController` with no camera hardware or emulator.
abstract class CameraFrameService {
  /// Requests permission (if needed) and starts the camera preview stream.
  ///
  /// Throws `CameraUnavailableException`
  /// (`domain/repositories/classifier_repository.dart`) on permission
  /// denial or hardware failure.
  Future<void> start();

  /// Live camera frames, roughly at the device's native frame rate; the
  /// consumer (the classifier repository) is responsible for throttling to
  /// the ~10-15 fps inference target.
  Stream<RawCameraFrame> get frames;

  /// Toggles between front and rear cameras while keeping [frames] open.
  Future<void> switchCamera();

  Future<void> stop();
}

/// Real implementation backed by `package:camera`.
///
/// All `package:camera` types (`CameraController`, `CameraDescription`,
/// `CameraImage`) are confined to this file; everything above/downstream of
/// [CameraFrameService] only ever sees [RawCameraFrame].
class CameraFrameServiceImpl implements CameraFrameService {
  CameraFrameServiceImpl({
    this.resolutionPreset = ResolutionPreset.low,
    this.preferredLensDirection = CameraLensDirection.front,
  }) : _activeLensDirection = preferredLensDirection;

  /// `low` is enough resolution for a 96x96 grayscale classifier input and
  /// keeps per-frame preprocessing cost down, which matters for hitting the
  /// ~10-15 fps inference target on the UI-adjacent isolate.
  final ResolutionPreset resolutionPreset;

  /// The front (selfie) camera is preferred by default so the player can look
  /// at the screen while showing their hand; falls back to whichever camera is
  /// available if a device only exposes a rear camera.
  final CameraLensDirection preferredLensDirection;

  CameraLensDirection _activeLensDirection;
  CameraController? _controller;
  StreamController<RawCameraFrame>? _frameStreamController;

  @override
  Future<void> start() async {
    if (_controller != null) {
      return; // Already started; safe to call again per the shared
      // start/stop lifecycle convention used across this app's services.
    }

    final streamController = StreamController<RawCameraFrame>.broadcast();
    try {
      await _openCameraForDirection(
        _activeLensDirection,
        streamController: streamController,
      );
    } catch (_) {
      await streamController.close();
      rethrow;
    }
    _frameStreamController = streamController;
  }

  @override
  Future<void> switchCamera() async {
    final targetDirection = _activeLensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final streamController = _frameStreamController;
    final previousController = _controller;
    if (previousController == null || streamController == null) {
      _activeLensDirection = targetDirection;
      return;
    }

    _controller = null;
    if (previousController.value.isStreamingImages) {
      await previousController.stopImageStream();
    }
    await previousController.dispose();

    await _openCameraForDirection(
      targetDirection,
      streamController: streamController,
    );
  }

  Future<void> _openCameraForDirection(
    CameraLensDirection direction, {
    required StreamController<RawCameraFrame> streamController,
  }) async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (error) {
      throw CameraUnavailableException(
        'Failed to enumerate available cameras.',
        cause: error,
      );
    }
    if (cameras.isEmpty) {
      throw const CameraUnavailableException(
        'No camera hardware is available on this device.',
      );
    }

    final description = cameras.firstWhere(
      (camera) => camera.lensDirection == direction,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      description,
      resolutionPreset,
      enableAudio: false,
      // YUV420 on Android, BGRA8888 on iOS — exactly the two plane shapes
      // `PreprocessFrameUseCase` knows how to read.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await controller.initialize();
    } on CameraException catch (error) {
      await controller.dispose();
      throw CameraUnavailableException(
        'Failed to initialize the camera.',
        cause: error,
      );
    }

    try {
      await controller.startImageStream((image) {
        if (!streamController.isClosed) {
          streamController.add(_toRawCameraFrame(image, description));
        }
      });
    } on CameraException catch (error) {
      await controller.dispose();
      throw CameraUnavailableException(
        'Failed to start the camera image stream.',
        cause: error,
      );
    }

    _controller = controller;
    _activeLensDirection = description.lensDirection;
  }

  @override
  Stream<RawCameraFrame> get frames {
    final streamController = _frameStreamController;
    if (streamController == null) {
      throw StateError(
        'CameraFrameServiceImpl.start() must complete successfully before '
        'reading frames.',
      );
    }
    return streamController.stream;
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    final streamController = _frameStreamController;
    _controller = null;
    _frameStreamController = null;

    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
    await streamController?.close();
  }

  RawCameraFrame _toRawCameraFrame(
    CameraImage image,
    CameraDescription description,
  ) {
    return RawCameraFrame(
      width: image.width,
      height: image.height,
      planeBytes: [for (final plane in image.planes) plane.bytes],
      bytesPerRow: [for (final plane in image.planes) plane.bytesPerRow],
      sensorOrientation: description.sensorOrientation,
      isFrontCamera: description.lensDirection == CameraLensDirection.front,
    );
  }
}
