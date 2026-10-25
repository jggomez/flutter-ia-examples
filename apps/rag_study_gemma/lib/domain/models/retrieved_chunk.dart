import 'document_chunk.dart';

/// Pairs a retrieved [DocumentChunk] with its semantic cosine similarity score.
class RetrievedChunk {
  const RetrievedChunk({required this.chunk, required this.similarityScore});

  final DocumentChunk chunk;
  final double similarityScore;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RetrievedChunk &&
        other.chunk == chunk &&
        other.similarityScore == similarityScore;
  }

  @override
  int get hashCode => Object.hash(chunk, similarityScore);
}
