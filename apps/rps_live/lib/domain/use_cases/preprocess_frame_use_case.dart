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
/// Output of [PreprocessFrameUseCase.preprocessWithPreview], bundling both the
/// normalized `[96 * 96]` tensor input and the upright `96x96` grayscale
/// preview bytes for the UI viewfinder.
class PreprocessedFrame {
  const PreprocessedFrame({
    required this.normalizedInput,
    required this.previewPixels,
  });

  final Float32List normalizedInput;
  final Uint8List previewPixels;
}

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
  Float32List call(RawCameraFrame frame) =>
      preprocessWithPreview(frame).normalizedInput;

  /// Produces both the normalized `Float32List` tensor input (canonically
  /// oriented with the wrist on the right border and contrast-normalized for
  /// real camera frames) and the upright/selfie-mirrored `96x96` grayscale
  /// [PreprocessedFrame.previewPixels] for the live viewfinder.
  PreprocessedFrame preprocessWithPreview(RawCameraFrame frame) {
    final grayscale = _extractGrayscale(frame);
    final square = _centerCropToSquare(grayscale, frame.width, frame.height);
    final resized = _resizeNearestNeighbor(
      square.pixels,
      square.side,
      outputSize,
    );
    final previewPixels = _orientPreview(
      resized,
      frame.sensorOrientation,
      frame.isFrontCamera,
    );

    var minPixel = 255;
    var maxPixel = 0;
    for (var i = 0; i < previewPixels.length; i++) {
      final v = previewPixels[i];
      if (v < minPixel) minPixel = v;
      if (v > maxPixel) maxPixel = v;
    }

    if (frame.width < outputSize ||
        frame.height < outputSize ||
        (maxPixel - minPixel) < 8) {
      final normalized = Float32List(outputSize * outputSize);
      for (var i = 0; i < resized.length; i++) {
        normalized[i] = resized[i] / 255.0;
      }
      return PreprocessedFrame(
        normalizedInput: normalized,
        previewPixels: previewPixels,
      );
    }

    final raw = Float32List(outputSize * outputSize);
    for (var i = 0; i < previewPixels.length; i++) {
      raw[i] = previewPixels[i] / 255.0;
    }

    final corners = <double>[
      _patchMean(raw, 0, 8, 0, 8),
      _patchMean(raw, outputSize - 8, outputSize, 0, 8),
      _patchMean(raw, 0, 8, outputSize - 8, outputSize),
      _patchMean(raw, outputSize - 8, outputSize, outputSize - 8, outputSize),
    ]..sort();
    final cornerBg = (corners[1] + corners[2]) * 0.5;

    final rightScore = _borderDeviation(raw, cornerBg, 90, 96, 16, 80);
    final bottomScore = _borderDeviation(raw, cornerBg, 16, 80, 90, 96);
    final leftScore = _borderDeviation(raw, cornerBg, 0, 6, 16, 80);
    final topScore = _borderDeviation(raw, cornerBg, 16, 80, 0, 6);

    var bestBorder = 'right';
    var bestScore = rightScore;
    if (bottomScore > bestScore) {
      bestBorder = 'bottom';
      bestScore = bottomScore;
    }
    if (leftScore > bestScore) {
      bestBorder = 'left';
      bestScore = leftScore;
    }
    if (topScore > bestScore) {
      bestBorder = 'top';
      bestScore = topScore;
    }

    final oriented = _orientWristToRight(raw, bestBorder);
    final centerMean = _patchMean(oriented, 24, 72, 24, 72);
    if (cornerBg > 0.55 && centerMean < cornerBg - 0.06) {
      for (var i = 0; i < oriented.length; i++) {
        oriented[i] = 1.0 - oriented[i];
      }
    }

    final sorted = Float32List.fromList(oriented)..sort();
    final p5 = sorted[(sorted.length * 0.05).floor()];
    final p95 = sorted[(sorted.length * 0.95).floor()];
    final span = p95 - p5;
    if (span >= 0.03) {
      for (var i = 0; i < oriented.length; i++) {
        oriented[i] = (0.12 + ((oriented[i] - p5) / span) * 0.80).clamp(
          0.0,
          1.0,
        );
      }
    }

    return PreprocessedFrame(
      normalizedInput: oriented,
      previewPixels: previewPixels,
    );
  }

  Uint8List _orientPreview(
    Uint8List src,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    final normalizedAngle = ((sensorOrientation % 360) + 360) % 360;
    var current = src;
    if (normalizedAngle == 90) {
      final rotated = Uint8List(outputSize * outputSize);
      for (var y = 0; y < outputSize; y++) {
        for (var x = 0; x < outputSize; x++) {
          rotated[y * outputSize + x] =
              current[(outputSize - 1 - x) * outputSize + y];
        }
      }
      current = rotated;
    } else if (normalizedAngle == 180) {
      final rotated = Uint8List(outputSize * outputSize);
      for (var y = 0; y < outputSize; y++) {
        for (var x = 0; x < outputSize; x++) {
          rotated[y * outputSize + x] =
              current[(outputSize - 1 - y) * outputSize + (outputSize - 1 - x)];
        }
      }
      current = rotated;
    } else if (normalizedAngle == 270) {
      final rotated = Uint8List(outputSize * outputSize);
      for (var y = 0; y < outputSize; y++) {
        for (var x = 0; x < outputSize; x++) {
          rotated[y * outputSize + x] =
              current[x * outputSize + (outputSize - 1 - y)];
        }
      }
      current = rotated;
    }

    if (isFrontCamera) {
      final flipped = Uint8List(outputSize * outputSize);
      for (var y = 0; y < outputSize; y++) {
        final rowStart = y * outputSize;
        for (var x = 0; x < outputSize; x++) {
          flipped[rowStart + x] = current[rowStart + (outputSize - 1 - x)];
        }
      }
      current = flipped;
    }
    return current;
  }

  double _patchMean(Float32List buf, int x0, int x1, int y0, int y1) {
    var sum = 0.0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final rowStart = y * outputSize;
      for (var x = x0; x < x1; x++) {
        sum += buf[rowStart + x];
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  double _borderDeviation(
    Float32List buf,
    double bg,
    int x0,
    int x1,
    int y0,
    int y1,
  ) {
    var sum = 0.0;
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final rowStart = y * outputSize;
      for (var x = x0; x < x1; x++) {
        sum += (buf[rowStart + x] - bg).abs();
        count++;
      }
    }
    return count == 0 ? 0.0 : sum / count;
  }

  Float32List _orientWristToRight(Float32List src, String border) {
    final out = Float32List(outputSize * outputSize);
    switch (border) {
      case 'bottom':
        for (var y = 0; y < outputSize; y++) {
          for (var x = 0; x < outputSize; x++) {
            out[y * outputSize + x] =
                src[x * outputSize + (outputSize - 1 - y)];
          }
        }
      case 'left':
        for (var y = 0; y < outputSize; y++) {
          final rowStart = y * outputSize;
          for (var x = 0; x < outputSize; x++) {
            out[rowStart + x] = src[rowStart + (outputSize - 1 - x)];
          }
        }
      case 'top':
        for (var y = 0; y < outputSize; y++) {
          for (var x = 0; x < outputSize; x++) {
            out[y * outputSize + x] =
                src[(outputSize - 1 - x) * outputSize + y];
          }
        }
      default:
        out.setAll(0, src);
    }
    return out;
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
