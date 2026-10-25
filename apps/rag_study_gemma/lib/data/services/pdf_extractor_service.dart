import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/error/app_exception.dart';
import '../../domain/models/extracted_pdf_page.dart';
import '../../domain/repositories/document_ingestion_repository.dart';

/// Service contract for validating a PDF file and extracting page-by-page text
/// off the main UI isolate.
abstract interface class PdfExtractorService {
  Future<List<ExtractedPdfPage>> extractPages(String filePath);
}

/// Pure-Dart PDF text extractor backed by `package:syncfusion_flutter_pdf`
/// running inside [Isolate.run] to preserve the 60/120fps UI frame budget.
class PdfExtractorServiceImpl implements PdfExtractorService {
  const PdfExtractorServiceImpl();

  static const List<int> _pdfMagicHeader = [0x25, 0x50, 0x44, 0x46, 0x2D];

  @override
  Future<List<ExtractedPdfPage>> extractPages(String filePath) async {
    final trimmedPath = filePath.trim();
    if (!trimmedPath.toLowerCase().endsWith('.pdf')) {
      throw InvalidPdfException(
        'Only .pdf files are supported. Selected path: $filePath',
      );
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      throw InvalidPdfException('PDF file does not exist at path: $filePath');
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        InvalidPdfException(
          'Failed to read PDF file at $filePath',
          cause: error,
        ),
        stackTrace,
      );
    }

    if (!_hasPdfMagicHeader(bytes)) {
      throw const InvalidPdfException(
        'Selected file is not a valid PDF (missing %PDF- magic header).',
      );
    }

    try {
      final pages = await Isolate.run(() => _extractPdfPagesSync(bytes));
      final hasNonEmptyText = pages.any((p) => p.text.trim().isNotEmpty);
      if (pages.isEmpty || !hasNonEmptyText) {
        throw const EmptyPdfTextException(
          'This PDF contains no selectable text (it may be a scanned image-only PDF).',
        );
      }
      return pages;
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        PdfExtractionException(
          'Failed to extract text from PDF at $filePath.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  static bool _hasPdfMagicHeader(Uint8List bytes) {
    if (bytes.length < _pdfMagicHeader.length) return false;
    final limit = math.min(bytes.length - _pdfMagicHeader.length, 1024);
    for (var offset = 0; offset <= limit; offset++) {
      var matched = true;
      for (var i = 0; i < _pdfMagicHeader.length; i++) {
        if (bytes[offset + i] != _pdfMagicHeader[i]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  static List<ExtractedPdfPage> _extractPdfPagesSync(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final pages = <ExtractedPdfPage>[];
      for (var i = 0; i < pageCount; i++) {
        final rawText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        pages.add(ExtractedPdfPage(pageNumber: i + 1, text: rawText));
      }
      return pages;
    } finally {
      document.dispose();
    }
  }
}
