/// Represents extracted text for a single 1-based page of a PDF document.
class ExtractedPdfPage {
  const ExtractedPdfPage({required this.pageNumber, required this.text});

  /// 1-based page number in the source PDF.
  final int pageNumber;

  /// Raw extracted text from this page.
  final String text;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExtractedPdfPage &&
        other.pageNumber == pageNumber &&
        other.text == text;
  }

  @override
  int get hashCode => Object.hash(pageNumber, text);
}
