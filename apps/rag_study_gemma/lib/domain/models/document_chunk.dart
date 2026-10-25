/// Represents a deterministic sliding-window text chunk from a PDF page.
class DocumentChunk {
  const DocumentChunk({
    required this.id,
    required this.docId,
    required this.docTitle,
    required this.pageNumber,
    required this.chunkIndex,
    required this.content,
  });

  final String id;
  final String docId;
  final String docTitle;
  final int pageNumber;
  final int chunkIndex;
  final String content;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DocumentChunk &&
        other.id == id &&
        other.docId == docId &&
        other.docTitle == docTitle &&
        other.pageNumber == pageNumber &&
        other.chunkIndex == chunkIndex &&
        other.content == content;
  }

  @override
  int get hashCode =>
      Object.hash(id, docId, docTitle, pageNumber, chunkIndex, content);
}
