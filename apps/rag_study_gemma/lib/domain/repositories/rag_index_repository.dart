import '../../core/error/app_exception.dart';
import '../models/document_chunk.dart';
import '../models/retrieved_chunk.dart';

/// Thrown when initializing, indexing, querying, or mutating the vector store fails.
class RagIndexException extends AppException {
  const RagIndexException(super.message, {super.cause});
}

/// Contract for the on-device `sqlite-vec` (`vec0`) semantic vector index.
abstract interface class RagIndexRepository {
  Future<void> initialize();

  Future<void> addChunks(
    List<DocumentChunk> chunks, {
    void Function(int current, int total)? onProgress,
  });

  Future<List<RetrievedChunk>> search({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  });

  Future<void> removeDocumentChunks(String docId, List<String> chunkIds);

  Future<void> dispose();
}
