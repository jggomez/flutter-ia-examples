import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/use_cases/validate_downloaded_models_use_case.dart';

void main() {
  group('ValidateDownloadedModelsUseCase', () {
    late ValidateDownloadedModelsUseCase useCase;

    setUp(() {
      useCase = const ValidateDownloadedModelsUseCase();
    });

    test(
      'returns true when both models exist and meet minimum byte lengths',
      () {
        final isValid = useCase(
          embeddingExists: true,
          embeddingByteLength: 157 * 1024 * 1024,
          llmExists: true,
          llmByteLength: 529 * 1024 * 1024,
        );

        expect(isValid, isTrue);
      },
    );

    test(
      'returns false when embedding model does not exist or is truncated',
      () {
        expect(
          useCase(
            embeddingExists: false,
            embeddingByteLength: 157 * 1024 * 1024,
            llmExists: true,
            llmByteLength: 529 * 1024 * 1024,
          ),
          isFalse,
        );

        expect(
          useCase(
            embeddingExists: true,
            embeddingByteLength: 50 * 1024 * 1024,
            llmExists: true,
            llmByteLength: 529 * 1024 * 1024,
          ),
          isFalse,
        );
      },
    );

    test('returns false when LLM model does not exist or is truncated', () {
      expect(
        useCase(
          embeddingExists: true,
          embeddingByteLength: 157 * 1024 * 1024,
          llmExists: false,
          llmByteLength: 529 * 1024 * 1024,
        ),
        isFalse,
      );

      expect(
        useCase(
          embeddingExists: true,
          embeddingByteLength: 157 * 1024 * 1024,
          llmExists: true,
          llmByteLength: 200 * 1024 * 1024,
        ),
        isFalse,
      );
    });

    test('respects custom minimum byte thresholds', () {
      expect(
        useCase(
          embeddingExists: true,
          embeddingByteLength: 1024,
          llmExists: true,
          llmByteLength: 2048,
          minEmbeddingBytes: 1000,
          minLlmBytes: 2000,
        ),
        isTrue,
      );
    });
  });
}
