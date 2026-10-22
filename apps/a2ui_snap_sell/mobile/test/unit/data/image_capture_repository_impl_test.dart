import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/data/repositories/image_capture_repository_impl.dart';
import 'package:mobile/data/services/image_picker_service.dart';
import 'package:mobile/domain/models/captured_photo.dart';

class _StubImagePickerService implements ImagePickerService {
  double? lastMaxWidth;
  double? lastMaxHeight;
  int? lastQuality;
  PhotoCaptureSource? lastSource;
  PickedRawImage? nextResult;

  @override
  Future<PickedRawImage?> pickImage({
    required PhotoCaptureSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
  }) async {
    lastSource = source;
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastQuality = imageQuality;
    return nextResult;
  }
}

void main() {
  group('ImageCaptureRepositoryImpl', () {
    late _StubImagePickerService pickerService;
    late ImageCaptureRepositoryImpl repository;

    setUp(() {
      pickerService = _StubImagePickerService();
      repository = ImageCaptureRepositoryImpl(pickerService: pickerService);
    });

    test('downscales captured image with maxWidth 1024, maxHeight 1024, imageQuality 82 and infers MIME type', () async {
      pickerService.nextResult = PickedRawImage(
        bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0]),
        name: 'car_front.jpg',
        mimeType: null,
      );

      final CapturedPhoto? photo = await repository.capturePhoto(
        PhotoCaptureSource.camera,
      );

      expect(pickerService.lastSource, equals(PhotoCaptureSource.camera));
      expect(pickerService.lastMaxWidth, equals(1024));
      expect(pickerService.lastMaxHeight, equals(1024));
      expect(pickerService.lastQuality, equals(82));
      expect(photo, isNotNull);
      expect(photo!.mimeType, equals('image/jpeg'));
      expect(photo.fileName, equals('car_front.jpg'));
    });

    test('returns null when user cancels picker', () async {
      pickerService.nextResult = null;
      final CapturedPhoto? photo = await repository.capturePhoto(
        PhotoCaptureSource.gallery,
      );
      expect(photo, isNull);
    });

    test('queues and dequeues follow-up photos in FIFO order', () {
      final CapturedPhoto first = CapturedPhoto(
        bytes: Uint8List.fromList(<int>[1, 2]),
        mimeType: 'image/jpeg',
        fileName: 'first.jpg',
        source: PhotoCaptureSource.camera,
      );
      final CapturedPhoto second = CapturedPhoto(
        bytes: Uint8List.fromList(<int>[3, 4]),
        mimeType: 'image/png',
        fileName: 'second.png',
        source: PhotoCaptureSource.gallery,
      );

      repository.queueFollowupPhoto(first);
      repository.queueFollowupPhoto(second);

      expect(repository.takeQueuedFollowupPhoto(), same(first));
      expect(repository.takeQueuedFollowupPhoto(), same(second));
      expect(repository.takeQueuedFollowupPhoto(), isNull);
    });
  });
}
