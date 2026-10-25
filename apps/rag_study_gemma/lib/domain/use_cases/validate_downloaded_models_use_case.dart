/// Validates that both EmbeddingGemma 2 and Gemma 3 1B IT `.litertlm` files
/// exist on disk and meet minimum expected byte thresholds.
class ValidateDownloadedModelsUseCase {
  const ValidateDownloadedModelsUseCase();

  static const int minEmbeddingModelSizeBytes = 100 * 1024 * 1024;
  static const int minLlmModelSizeBytes = 400 * 1024 * 1024;

  bool call({
    required bool embeddingExists,
    required int embeddingByteLength,
    required bool llmExists,
    required int llmByteLength,
    int minEmbeddingBytes = minEmbeddingModelSizeBytes,
    int minLlmBytes = minLlmModelSizeBytes,
  }) {
    if (!embeddingExists || !llmExists) {
      return false;
    }
    return embeddingByteLength >= minEmbeddingBytes &&
        llmByteLength >= minLlmBytes;
  }

  bool isValidEmbeddingModel(
    int byteLength, {
    int minBytes = minEmbeddingModelSizeBytes,
  }) => byteLength >= minBytes;

  bool isValidLlmModel(int byteLength, {int minBytes = minLlmModelSizeBytes}) =>
      byteLength >= minBytes;
}
