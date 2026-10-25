/// Represents an imported and indexed PDF study document in the user's library.
class StudyDocument {
  const StudyDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    required this.chunkCount,
    required this.indexedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final String filePath;
  final int pageCount;
  final int chunkCount;
  final DateTime indexedAt;

  StudyDocument copyWith({
    String? id,
    String? title,
    String? fileName,
    String? filePath,
    int? pageCount,
    int? chunkCount,
    DateTime? indexedAt,
  }) {
    return StudyDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      pageCount: pageCount ?? this.pageCount,
      chunkCount: chunkCount ?? this.chunkCount,
      indexedAt: indexedAt ?? this.indexedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudyDocument &&
        other.id == id &&
        other.title == title &&
        other.fileName == fileName &&
        other.filePath == filePath &&
        other.pageCount == pageCount &&
        other.chunkCount == chunkCount &&
        other.indexedAt == indexedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    fileName,
    filePath,
    pageCount,
    chunkCount,
    indexedAt,
  );
}
