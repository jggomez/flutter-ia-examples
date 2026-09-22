import 'dart:typed_data';

/// A plain-Dart, plugin-agnostic view of a single camera frame.
///
/// `package:camera`'s `CameraImage` is a platform-channel-backed type that
/// is awkward (and on some platforms impossible) to construct in a plain
/// `test/` unit test. [RawCameraFrame] is the boundary type the domain
/// preprocessing math actually operates on: `data/services/camera_frame_service.dart`
/// is responsible for mapping a real `CameraImage` into this shape; tests
/// construct [RawCameraFrame] directly with synthetic byte planes.
///
/// Kept intentionally close to `CameraImage`'s YUV420/BGRA8888 plane model
/// so the mapping in the data layer is a thin, low-risk adapter.
class RawCameraFrame {
  const RawCameraFrame({
    required this.width,
    required this.height,
    required this.planeBytes,
    required this.bytesPerRow,
  });

  final int width;
  final int height;

  /// Raw plane bytes (one entry per image plane, e.g. Y/U/V or a single
  /// packed plane), in the source color format. Grayscale conversion,
  /// center-crop and resize happen in
  /// `domain/use_cases/preprocess_frame_use_case.dart`.
  final List<Uint8List> planeBytes;

  /// Row stride for each corresponding entry in [planeBytes].
  final List<int> bytesPerRow;
}
