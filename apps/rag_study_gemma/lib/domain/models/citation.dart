/// Represents a source citation linking an assistant answer to a PDF page excerpt.
class Citation {
  const Citation({
    required this.id,
    required this.docId,
    required this.docTitle,
    required this.pageNumber,
    required this.snippet,
    required this.similarityScore,
  });

  final String id;
  final String docId;
  final String docTitle;
  final int pageNumber;
  final String snippet;
  final double similarityScore;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Citation &&
        other.id == id &&
        other.docId == docId &&
        other.docTitle == docTitle &&
        other.pageNumber == pageNumber &&
        other.snippet == snippet &&
        other.similarityScore == similarityScore;
  }

  @override
  int get hashCode =>
      Object.hash(id, docId, docTitle, pageNumber, snippet, similarityScore);
}
