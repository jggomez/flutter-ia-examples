import 'dart:math' as math;
import 'dart:typed_data';

import '../models/raw_camera_frame.dart';

/// Pure Dart-side preprocessing: camera frame -> center-crop to square ->
/// resize to 96x96 -> grayscale -> normalize to `float32 [0, 1]`.
///
/// This is the exact math the ML model contract requires (input tensor
/// `[1, 96, 96, 1]`, grayscale, `pixel / 255.0`). It is deliberately a plain
/// function over [RawCameraFrame] with no Flutter/camera/tflite imports so
/// `flutter-implementer` can TDD it with synthetic byte arrays and assert
/// exact output values — no camera or device required.
///
/// The real classifier pipeline (`data/repositories/classifier_repository_impl.dart`)
/// must run this off the UI isolate (`Isolate.run` / `compute`) to hit the
/// ~10-15 fps target without jank.
///
/// ## Plane format contract
///
/// [RawCameraFrame] deliberately mirrors `package:camera`'s `CameraImage`
/// plane model (see that class's doc comment), which only ever hands us one
/// of two shapes in practice:
///
/// - **BGRA8888** (iOS, single packed plane): `planeBytes.length == 1` and
///   the row stride is at least 4 bytes per pixel. Luma is derived from the
///   B/G/R channels with the standard Rec. 601 luma weights; alpha is
///   ignored.
/// - **YUV420 (planar or semi-planar)** (Android): the first plane is
///   full-resolution luma (Y) — already the exact grayscale intensity a
///   classifier needs — so it is read directly and any chroma (U/V) planes
///   are ignored entirely. A single already-grayscale plane (one byte per
///   pixel) is treated the same way, which also make this trivial to feed
///   synthetic single-channel fixtures in tests.
///
/// Row stride ([RawCameraFrame.bytesPerRow]) is always honored explicitly
/// (never assumed to equal `width` or `width * bytesPerPixel`), since camera
/// buffers are frequently padded.
class PreprocessFrameUseCase {
  const PreprocessFrameUseCase();

  /// Side length (in pixels) of the square output the model expects.
  static const int outputSize = 96;

  /// A single packed plane is treated as BGRA8888 once its row stride
  /// implies at least this many bytes per pixel; otherwise a single plane is
  /// treated as an already-grayscale (1 byte per pixel) buffer.
  static const int _bgraMinBytesPerPixel = 4;

  /// Returns a flat, row-major `Float32List` of length `96 * 96` (matching
  /// the model's `[1, 96, 96, 1]` input tensor once reshaped by the caller),
  /// with every value normalized to `[0, 1]`.
  Float32List call(RawCameraFrame frame) {
    final grayscale = _extractGrayscale(frame);
    final square = _centerCropToSquare(grayscale, frame.width, frame.height);
    final resized = _resizeNearestNeighbor(
      square.pixels,
      square.side,
      outputSize,
    );

    final normalized = Float32List(outputSize * outputSize);
    for (var i = 0; i < resized.length; i++) {
      normalized[i] = resized[i] / 255.0;
    }
    return normalized;
  }

  /// Extracts a row-major, one-byte-per-pixel luma buffer at the frame's
  /// original `width x height`, per the plane format contract documented on
  /// this class.
  Uint8List _extractGrayscale(RawCameraFrame frame) {
    final width = frame.width;
    final height = frame.height;
    final stride = frame.bytesPerRow[0];
    final bytesPerPixel = width == 0 ? 1 : stride ~/ width;
    final isPackedBgra =
        frame.planeBytes.length == 1 && bytesPerPixel >= _bgraMinBytesPerPixel;

    final out = Uint8List(width * height);
    final plane = frame.planeBytes[0];

    if (isPackedBgra) {
      for (var y = 0; y < height; y++) {
        final rowStart = y * stride;
        for (var x = 0; x < width; x++) {
          final pixelStart = rowStart + x * 4;
          final b = plane[pixelStart];
          final g = plane[pixelStart + 1];
          final r = plane[pixelStart + 2];
          out[y * width + x] = (0.299 * r + 0.587 * g + 0.114 * b)
              .round()
              .clamp(0, 255);
        }
      }
    } else {
      // Already-grayscale single plane, or the Y (luma) plane of a
      // planar/semi-planar YUV420 frame — one byte per pixel either way.
      for (var y = 0; y < height; y++) {
        final rowStart = y * stride;
        for (var x = 0; x < width; x++) {
          out[y * width + x] = plane[rowStart + x];
        }
      }
    }
    return out;
  }

  /// Crops [gray] (row-major, `width x height`) to a centered
  /// `side x side` square, where `side = min(width, height)`.
  _SquareBuffer _centerCropToSquare(Uint8List gray, int width, int height) {
    final side = math.min(width, height);
    if (width == side && height == side) {
      return _SquareBuffer(gray, side);
    }

    final offsetX = (width - side) ~/ 2;
    final offsetY = (height - side) ~/ 2;
    final out = Uint8List(side * side);
    for (var y = 0; y < side; y++) {
      final srcRowStart = (y + offsetY) * width + offsetX;
      out.setRange(y * side, y * side + side, gray, srcRowStart);
    }
    return _SquareBuffer(out, side);
  }

  /// Nearest-neighbor resize of a `srcSide x srcSide` square to
  /// `dstSide x dstSide`. Chosen over bilinear/bicubic interpolation for
  /// determinism (exact, easily-asserted output values in tests) and speed,
  /// since the model was trained on similarly simple downsampling; revisit
  /// if classifier accuracy motivates smoother interpolation.
  Uint8List _resizeNearestNeighbor(Uint8List src, int srcSide, int dstSide) {
    if (srcSide == dstSide) {
      return src;
    }
    final out = Uint8List(dstSide * dstSide);
    for (var y = 0; y < dstSide; y++) {
      final srcY = (y * srcSide) ~/ dstSide;
      final srcRowStart = srcY * srcSide;
      final dstRowStart = y * dstSide;
      for (var x = 0; x < dstSide; x++) {
        final srcX = (x * srcSide) ~/ dstSide;
        out[dstRowStart + x] = src[srcRowStart + srcX];
      }
    }
    return out;
  }
}

class _SquareBuffer {
  const _SquareBuffer(this.pixels, this.side);

  final Uint8List pixels;
  final int side;
}
