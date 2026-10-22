import 'package:mime/mime.dart';

import '../../domain/repositories/image_capture_repository.dart';
import '../services/image_picker_service.dart';

/// Concrete implementation of [ImageCaptureService] using [ImagePickerService].
class ImagePickerCaptureService implements ImageCaptureService {
  /// Creates an [ImagePickerCaptureService].
  ImagePickerCaptureService({
    ImagePickerService? pickerService,
    this.maxPayloadBytes = defaultMaxPayloadBytes,
  }) : _pickerService = pickerService ?? ImagePickerService();

  /// Hard cap on compressed image size (1.5 MB per ADR 0001).
  static const int defaultMaxPayloadBytes = 1500000;

  final ImagePickerService _pickerService;

  /// Maximum allowed image payload size in bytes.
  final int maxPayloadBytes;

  final List<CapturedPhoto> _queuedFollowupPhotos = <CapturedPhoto>[];

  @override
  Future<CapturedPhoto?> capturePhoto(
    PhotoCaptureSource source, {
    double maxWidth = 1024,
    double maxHeight = 1024,
    int imageQuality = 82,
  }) async {
    final PickedRawImage? picked = await _pickerService.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;

    if (picked.bytes.lengthInBytes > maxPayloadBytes) {
      throw ImageTooLargeException(
        actualBytes: picked.bytes.lengthInBytes,
        maxBytes: maxPayloadBytes,
      );
    }

    final String resolvedMime =
        picked.mimeType ??
        lookupMimeType(picked.name, headerBytes: picked.bytes) ??
        'image/jpeg';

    return CapturedPhoto(
      bytes: picked.bytes,
      mimeType: resolvedMime,
      fileName: picked.name,
      source: source,
    );
  }

  @override
  void queueFollowupPhoto(CapturedPhoto photo) {
    _queuedFollowupPhotos.add(photo);
  }

  @override
  CapturedPhoto? takeQueuedFollowupPhoto() {
    if (_queuedFollowupPhotos.isEmpty) return null;
    return _queuedFollowupPhotos.removeAt(0);
  }
}

/// Alias matching ADR 0006 naming.
typedef ImageCaptureRepositoryImpl = ImagePickerCaptureService;
