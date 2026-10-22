import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../domain/models/classification_result.dart';
import '../../../domain/models/move.dart';

/// Shared live-camera viewfinder and gesture-feedback card used by both
/// `VsAiScreen` ("Tú vs. IA") and `PracticeScreen` ("Práctica libre").
///
/// Renders [ClassificationResult.previewPixels] (`96x96` grayscale crop) via an
/// in-memory 24-bit BMP and `Image.memory(..., gaplessPlayback: true)` so
/// `lib/ui/**` remains 100% free of `package:camera` imports.
class CameraViewfinder extends StatelessWidget {
  const CameraViewfinder({
    super.key = const ValueKey('cameraViewfinder'),
    required this.liveResult,
    this.onSwitchCamera,
    this.overlay,
    this.showInstructions = true,
  });

  final ClassificationResult? liveResult;
  final VoidCallback? onSwitchCamera;
  final Widget? overlay;
  final bool showInstructions;

  static const int _side = 96;

  @override
  Widget build(BuildContext context) {
    final result = liveResult;
    final previewPixels = result?.previewPixels;
    final hasPreview =
        previewPixels != null && previewPixels.length == _side * _side;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                key: const ValueKey('liveGestureBadge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  result == null
                      ? 'Cámara activa · Muestra tu mano 👋'
                      : 'IA ve: ${_moveBadgeLabel(result.topMove)} '
                            '· ${(result.confidenceFor(result.topMove) * 100).round()}%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (onSwitchCamera != null) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('switchCameraButton'),
                onPressed: onSwitchCamera,
                tooltip: 'Cambiar cámara (frontal / trasera)',
                icon: const Icon(Icons.cameraswitch),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 168,
          height: 168,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary, width: 2.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasPreview)
                      Image.memory(
                        _encodeGrayscale96ToBmp(previewPixels),
                        gaplessPlayback: true,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                      )
                    else
                      const Center(
                        child: Icon(
                          Icons.back_hand_outlined,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    if (overlay != null)
                      Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: overlay,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showInstructions) ...[
          const SizedBox(height: 8),
          Text(
            '1. Coloca tu mano frente a la cámara dentro del recuadro · '
            '2. Verifica arriba qué jugada detecta la IA · '
            '3. Toca «Empezar ronda» y mantén tu gesto en el 3-2-1',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _moveBadgeLabel(Move move) => switch (move) {
    Move.paper => '✋ Papel',
    Move.rock => '✊ Piedra',
    Move.scissors => '✌️ Tijera',
  };

  /// Encodes a `96x96` 8-bit grayscale buffer into an uncompressed 24-bit BMP.
  static Uint8List _encodeGrayscale96ToBmp(Uint8List gray) {
    const headerSize = 54;
    const imageBytes = _side * _side * 3;
    const fileSize = headerSize + imageBytes;

    final bmp = Uint8List(fileSize);
    final header = ByteData.sublistView(bmp, 0, headerSize);
    // 'BM' signature
    header.setUint8(0, 0x42);
    header.setUint8(1, 0x4D);
    header.setUint32(2, fileSize, Endian.little);
    header.setUint32(10, headerSize, Endian.little);
    // BITMAPINFOHEADER (40 bytes)
    header.setUint32(14, 40, Endian.little);
    header.setInt32(18, _side, Endian.little);
    header.setInt32(22, _side, Endian.little); // positive = bottom-up rows
    header.setUint16(26, 1, Endian.little); // planes
    header.setUint16(28, 24, Endian.little); // 24 bpp (BGR)
    header.setUint32(34, imageBytes, Endian.little);
    header.setInt32(38, 2835, Endian.little);
    header.setInt32(42, 2835, Endian.little);

    var outOffset = headerSize;
    for (var bmpRow = 0; bmpRow < _side; bmpRow++) {
      final srcRowStart = (_side - 1 - bmpRow) * _side;
      for (var x = 0; x < _side; x++) {
        final v = gray[srcRowStart + x];
        bmp[outOffset++] = v;
        bmp[outOffset++] = v;
        bmp[outOffset++] = v;
      }
    }
    return bmp;
  }
}
