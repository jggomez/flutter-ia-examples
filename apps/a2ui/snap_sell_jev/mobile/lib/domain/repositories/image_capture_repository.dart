import '../models/captured_photo.dart';

export '../models/captured_photo.dart' show CapturedPhoto, PhotoCaptureSource;

/// Exception thrown when a captured image exceeds the maximum allowed payload size.
class ImageTooLargeException implements Exception {
  /// Creates an [ImageTooLargeException].
  const ImageTooLargeException({
    required this.actualBytes,
    required this.maxBytes,
  });

  /// Actual byte length of the picked image.
  final int actualBytes;

  /// Maximum allowed byte length.
  final int maxBytes;

  @override
  String toString() =>
      'Selected image is ${(actualBytes / 1024).round()} KB, which exceeds the '
      'maximum limit of ${(maxBytes / 1024).round()} KB.';
}

/// Domain contract for capturing and queuing compressed photos from camera or gallery.
abstract interface class ImageCaptureService {
  /// Captures or picks a photo from [source], resizing to at most
  /// [maxWidth]x[maxHeight] at JPEG [imageQuality].
  ///
  /// Returns `null` if the user cancels the picker.
  Future<CapturedPhoto?> capturePhoto(
    PhotoCaptureSource source, {
    double maxWidth = 1024,
    double maxHeight = 1024,
    int imageQuality = 82,
  });

  /// Queues a follow-up [photo] captured inside a `PhotoRequest` widget so the
  /// outgoing `UserActionEvent` turn attaches its binary `DataPart`.
  void queueFollowupPhoto(CapturedPhoto photo);

  /// Dequeues the next pending follow-up photo, if any.
  CapturedPhoto? takeQueuedFollowupPhoto();
}

/// Alias matching repository naming convention in ADR 0004 / ADR 0006.
typedef ImageCaptureRepository = ImageCaptureService;
