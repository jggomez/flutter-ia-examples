import 'package:event_llm_wiki/domain/use_cases/validate_downloaded_model_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

const _useCase = ValidateDownloadedModelUseCase();

void main() {
  group('ValidateDownloadedModelUseCase', () {
    test('rejects a file well below minValidSizeBytes (a truncated '
        'download)', () {
      expect(_useCase(fileSizeBytes: 1024), isFalse);
    });

    test('rejects a file exactly one byte below minValidSizeBytes', () {
      expect(
        _useCase(
          fileSizeBytes: ValidateDownloadedModelUseCase.minValidSizeBytes - 1,
        ),
        isFalse,
      );
    });

    test('accepts a file exactly at minValidSizeBytes', () {
      expect(
        _useCase(
          fileSizeBytes: ValidateDownloadedModelUseCase.minValidSizeBytes,
        ),
        isTrue,
      );
    });

    test('accepts a file well above minValidSizeBytes (the real ~529 MB '
        'model)', () {
      expect(_useCase(fileSizeBytes: 529 * 1000 * 1000), isTrue);
    });

    test('rejects a zero-byte file', () {
      expect(_useCase(fileSizeBytes: 0), isFalse);
    });
  });
}
