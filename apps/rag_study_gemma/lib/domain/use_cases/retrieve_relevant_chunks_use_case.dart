import '../models/retrieved_chunk.dart';
import '../repositories/rag_index_repository.dart';

/// Queries the on-device semantic vector index and returns ranked [RetrievedChunk]s.
class RetrieveRelevantChunksUseCase {
  const RetrieveRelevantChunksUseCase();

  Future<List<RetrievedChunk>> call({
    required String query,
    required RagIndexRepository ragIndexRepository,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final rawResults = await ragIndexRepository.search(
      query: trimmedQuery,
      topK: topK,
      minSimilarity: minSimilarity,
      filterDocId: filterDocId,
    );

    final filtered =
        rawResults
            .where((item) => item.similarityScore >= minSimilarity)
            .toList()
          ..sort((a, b) => b.similarityScore.compareTo(a.similarityScore));

    if (filtered.length > topK) {
      return filtered.sublist(0, topK);
    }
    return filtered;
  }
}
