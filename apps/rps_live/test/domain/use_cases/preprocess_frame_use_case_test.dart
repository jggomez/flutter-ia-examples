import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/raw_camera_frame.dart';
import 'package:rps_live/domain/use_cases/preprocess_frame_use_case.dart';

void main() {
  const useCase = PreprocessFrameUseCase();
  const outputLength = 96 * 96;

  group('output shape', () {
    test(
      'is always 96*96 float32 values in [0, 1] regardless of input size',
      () {
        for (final size in <(int, int)>[(2, 2), (4, 2), (200, 100), (96, 96)]) {
          final (width, height) = size;
          final frame = RawCameraFrame(
            width: width,
            height: height,
            planeBytes: [Uint8List(width * height)],
            bytesPerRow: [width],
          );

          final result = useCase(frame);

          expect(result.length, outputLength, reason: 'for size $size');
          expect(result.every((v) => v >= 0.0 && v <= 1.0), isTrue);
        }
      },
    );
  });

  group('BGRA8888 (single packed plane) grayscale + normalize', () {
    test('converts a 2x2 square frame with no cropping needed', () {
      // 2x2 BGRA8888 image, 4 bytes/pixel, no row padding.
      // Pixel layout (row-major): (0,0) black, (1,0) white,
      //                            (0,1) pure red, (1,1) pure blue.
      final bytes = Uint8List.fromList([
        // row 0
        0, 0, 0, 255, // (0,0) B=0 G=0 R=0 A=255 -> black -> luma 0
        255,
        255,
        255,
        255, // (1,0) B=255 G=255 R=255 A=255 -> white -> luma 255
        // row 1
        0,
        0,
        255,
        255, // (0,1) B=0 G=0 R=255 -> pure red -> luma round(0.299*255)=76
        255,
        0,
        0,
        255, // (1,1) B=255 G=0 R=0 -> pure blue -> luma round(0.114*255)=29
      ]);
      final frame = RawCameraFrame(
        width: 2,
        height: 2,
        planeBytes: [bytes],
        bytesPerRow: [8], // 2 pixels * 4 bytes, no padding
      );

      final result = useCase(frame);

      expect(result.length, outputLength);
      // 2x2 -> 96x96 nearest-neighbor upscale: each source pixel maps to a
      // contiguous 48x48 quadrant of the output.
      double at(int x, int y) => result[y * 96 + x];

      expect(at(0, 0), closeTo(0.0, 1e-6)); // top-left quadrant -> (0,0) black
      expect(
        at(95, 0),
        closeTo(1.0, 1e-6),
      ); // top-right quadrant -> (1,0) white
      expect(at(0, 95), closeTo(76 / 255, 1e-6)); // bottom-left -> (0,1) red
      expect(at(95, 95), closeTo(29 / 255, 1e-6)); // bottom-right -> (1,1) blue
    });

    test(
      'honors row stride (bytesPerRow) larger than width * bytesPerPixel',
      () {
        // 2x2 image but each row is padded with 4 extra junk bytes.
        final bytes = Uint8List.fromList([
          // row 0: pixel(0,0)=white, pixel(1,0)=black, then 4 padding bytes
          255, 255, 255, 255, 0, 0, 0, 255, 9, 9, 9, 9,
          // row 1: pixel(0,1)=white, pixel(1,1)=black, then 4 padding bytes
          255, 255, 255, 255, 0, 0, 0, 255, 9, 9, 9, 9,
        ]);
        final frame = RawCameraFrame(
          width: 2,
          height: 2,
          planeBytes: [bytes],
          bytesPerRow: [12], // 8 real bytes + 4 padding bytes per row
        );

        final result = useCase(frame);
        double at(int x, int y) => result[y * 96 + x];

        expect(at(0, 0), closeTo(1.0, 1e-6));
        expect(at(95, 0), closeTo(0.0, 1e-6));
        expect(at(0, 95), closeTo(1.0, 1e-6));
        expect(at(95, 95), closeTo(0.0, 1e-6));
      },
    );
  });

  group('YUV (multi-plane) grayscale via luma plane', () {
    test('uses only the first (Y) plane and ignores chroma planes', () {
      // 2x2 luma plane with distinct values; U/V planes contain
      // out-of-range/garbage bytes that must never be read.
      final yPlane = Uint8List.fromList([10, 200, 50, 150]);
      final uPlane = Uint8List.fromList([255, 255]);
      final vPlane = Uint8List.fromList([255, 255]);
      final frame = RawCameraFrame(
        width: 2,
        height: 2,
        planeBytes: [yPlane, uPlane, vPlane],
        bytesPerRow: [2, 1, 1],
      );

      final result = useCase(frame);
      double at(int x, int y) => result[y * 96 + x];

      expect(at(0, 0), closeTo(10 / 255, 1e-6));
      expect(at(95, 0), closeTo(200 / 255, 1e-6));
      expect(at(0, 95), closeTo(50 / 255, 1e-6));
      expect(at(95, 95), closeTo(150 / 255, 1e-6));
    });

    test('honors a padded luma row stride', () {
      // 2x2 logical luma plane, but each row is stored with 2 padding bytes.
      final yPlane = Uint8List.fromList([1, 2, 77, 77, 3, 4, 77, 77]);
      final frame = RawCameraFrame(
        width: 2,
        height: 2,
        planeBytes: [yPlane, Uint8List(4)],
        bytesPerRow: [4, 4],
      );

      final result = useCase(frame);
      double at(int x, int y) => result[y * 96 + x];

      expect(at(0, 0), closeTo(1 / 255, 1e-6));
      expect(at(95, 0), closeTo(2 / 255, 1e-6));
      expect(at(0, 95), closeTo(3 / 255, 1e-6));
      expect(at(95, 95), closeTo(4 / 255, 1e-6));
    });
  });

  group('center-crop to square before resize', () {
    test('crops a wide (landscape) frame around its horizontal center', () {
      // 4x2 luma plane. Center-crop to a 2x2 square drops the outermost
      // column on each side (offsetX = (4-2)~/2 = 1), keeping columns 1-2.
      // Row-major values 0..7:
      //  row0: 0 1 2 3
      //  row1: 4 5 6 7
      // Cropped 2x2 (columns 1-2): row0: 1 2 ; row1: 5 6
      final yPlane = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final frame = RawCameraFrame(
        width: 4,
        height: 2,
        planeBytes: [yPlane],
        bytesPerRow: [4],
      );

      final result = useCase(frame);
      double at(int x, int y) => result[y * 96 + x];

      expect(at(0, 0), closeTo(1 / 255, 1e-6));
      expect(at(95, 0), closeTo(2 / 255, 1e-6));
      expect(at(0, 95), closeTo(5 / 255, 1e-6));
      expect(at(95, 95), closeTo(6 / 255, 1e-6));
    });

    test('crops a tall (portrait) frame around its vertical center', () {
      // 2x4 luma plane. Center-crop to 2x2 drops the outermost row on each
      // side (offsetY = (4-2)~/2 = 1), keeping rows 1-2.
      // rows: [0,1] [2,3] [4,5] [6,7] -> keep rows 1-2: [2,3] [4,5]
      final yPlane = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final frame = RawCameraFrame(
        width: 2,
        height: 4,
        planeBytes: [yPlane],
        bytesPerRow: [2],
      );

      final result = useCase(frame);
      double at(int x, int y) => result[y * 96 + x];

      expect(at(0, 0), closeTo(2 / 255, 1e-6));
      expect(at(95, 0), closeTo(3 / 255, 1e-6));
      expect(at(0, 95), closeTo(4 / 255, 1e-6));
      expect(at(95, 95), closeTo(5 / 255, 1e-6));
    });
  });

  group('preprocessWithPreview & previewPixels orientation', () {
    test('rotates previewPixels by sensorOrientation and mirrors when '
        'isFrontCamera is true', () {
      // Create a 96x96 frame where only pixel (x=0, y=0) is 255 and the rest
      // are 0.
      // Rotating 90° CW moves (0, 0) -> (95, 0).
      // Mirroring horizontally (isFrontCamera: true) moves (95, 0) -> (0, 0).
      // Rotating 270° CW moves (0, 0) -> (0, 95), and mirroring moves
      // (0, 95) -> (95, 95).
      final yPlane = Uint8List(96 * 96);
      yPlane[0] = 255;
      final frame = RawCameraFrame(
        width: 96,
        height: 96,
        planeBytes: [yPlane],
        bytesPerRow: [96],
        sensorOrientation: 270,
        isFrontCamera: true,
      );

      final preprocessed = useCase.preprocessWithPreview(frame);

      expect(preprocessed.previewPixels.length, outputLength);
      expect(preprocessed.previewPixels[95 * 96 + 95], 255);
      expect(preprocessed.previewPixels[0], 0);
    });
  });

  group('canonical wrist-border auto-orientation & contrast normalization', () {
    RawCameraFrame buildHandFrame({
      required String wristBorder,
      int bgValue = 40,
      int handValue = 220,
    }) {
      final yPlane = Uint8List.fromList(List<int>.filled(96 * 96, bgValue));
      // Fill center hand region (32..64, 32..64)
      for (var y = 32; y < 64; y++) {
        for (var x = 32; x < 64; x++) {
          yPlane[y * 96 + x] = handValue;
        }
      }
      // Fill wrist crossing the specified border along middle span [30..66)
      for (var i = 30; i < 66; i++) {
        for (var d = 0; d < 6; d++) {
          switch (wristBorder) {
            case 'right':
              yPlane[i * 96 + (90 + d)] = handValue;
            case 'bottom':
              yPlane[(90 + d) * 96 + i] = handValue;
            case 'left':
              yPlane[i * 96 + d] = handValue;
            case 'top':
              yPlane[d * 96 + i] = handValue;
          }
        }
      }
      return RawCameraFrame(
        width: 96,
        height: 96,
        planeBytes: [yPlane],
        bytesPerRow: [96],
      );
    }

    for (final border in ['right', 'bottom', 'left', 'top']) {
      test('rotates/flips wrist on $border border to canonical right edge '
          '(x = 95)', () {
        final frame = buildHandFrame(wristBorder: border);

        final normalized = useCase(frame);
        double at(int x, int y) => normalized[y * 96 + x];

        // After canonical orientation, the right border middle (x=95, y=48)
        // must have the bright wrist (~0.92), whereas the other three borders'
        // midpoints remain background (~0.12).
        expect(
          at(95, 48),
          greaterThan(0.8),
          reason: 'right border for $border',
        );
        expect(at(0, 48), lessThan(0.3), reason: 'left border for $border');
        expect(at(48, 0), lessThan(0.3), reason: 'top border for $border');
        expect(at(48, 95), lessThan(0.3), reason: 'bottom border for $border');
      });
    }

    test('inverts contrast when hand in center is darker than a bright '
        'background', () {
      // Bright wall (bg=230) with dark hand/wrist (hand=40) entering from bottom
      final frame = buildHandFrame(
        wristBorder: 'bottom',
        bgValue: 230,
        handValue: 40,
      );

      final normalized = useCase(frame);
      double at(int x, int y) => normalized[y * 96 + x];

      // Center hand and canonical right wrist become bright (> 0.8), corners
      // become dark (< 0.3).
      expect(at(48, 48), greaterThan(0.8));
      expect(at(95, 48), greaterThan(0.8));
      expect(at(2, 2), lessThan(0.3));
    });
  });
}
