import 'package:flutter/foundation.dart';

/// Source from which a user photo is captured.
enum PhotoCaptureSource {
  /// Device camera.
  camera,

  /// Device photo gallery.
  gallery,
}

/// Immutable value object representing a compressed user photo ready for A2A upload.
@immutable
class CapturedPhoto {
  /// Creates a [CapturedPhoto].
  const CapturedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.source,
  });

  /// Compressed image bytes (JPEG).
  final Uint8List bytes;

  /// MIME type of the image (typically `image/jpeg`).
  final String mimeType;

  /// File name of the captured image.
  final String fileName;

  /// Capture source (camera or gallery).
  final PhotoCaptureSource source;

  /// Local URI key used to look up in-memory image bytes in catalog widgets.
  String get localUri => 'local://photo/$fileName';
}
