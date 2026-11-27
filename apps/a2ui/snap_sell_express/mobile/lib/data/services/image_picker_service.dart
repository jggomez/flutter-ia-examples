import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../domain/models/captured_photo.dart';

/// Raw picked image data returned by [ImagePickerService].
class PickedRawImage {
  /// Creates a [PickedRawImage].
  const PickedRawImage({
    required this.bytes,
    required this.name,
    this.mimeType,
  });

  /// Picked file bytes.
  final Uint8List bytes;

  /// Picked file name.
  final String name;

  /// Optional MIME type reported by the platform.
  final String? mimeType;
}

/// Thin pass-through service over `package:image_picker`.
class ImagePickerService {
  /// Creates an [ImagePickerService].
  ImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Invokes the platform camera or gallery picker with size and quality bounds.
  Future<PickedRawImage?> pickImage({
    required PhotoCaptureSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
  }) async {
    final ImageSource imageSource = switch (source) {
      PhotoCaptureSource.camera => ImageSource.camera,
      PhotoCaptureSource.gallery => ImageSource.gallery,
    };
    final XFile? file = await _picker.pickImage(
      source: imageSource,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
    if (file == null) return null;
    final Uint8List bytes = await file.readAsBytes();
    return PickedRawImage(
      bytes: bytes,
      name: file.name.isEmpty ? 'snap_sell_photo.jpg' : file.name,
      mimeType: file.mimeType,
    );
  }
}
