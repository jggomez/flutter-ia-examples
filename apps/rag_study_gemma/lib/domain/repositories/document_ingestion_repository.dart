import '../../core/error/app_exception.dart';
import '../models/ingestion_progress.dart';
import '../models/study_document.dart';

/// Thrown when a selected file is missing, does not have a `.pdf` extension,
/// or lacks the `%PDF-` magic header.
class InvalidPdfException extends AppException {
  const InvalidPdfException(super.message, {super.cause});
}

/// Thrown when extracting text from a PDF fails.
class PdfExtractionException extends AppException {
  const PdfExtractionException(super.message, {super.cause});
}

/// Thrown when a PDF contains zero selectable/extractable text across all pages.
class EmptyPdfTextException extends PdfExtractionException {
  const EmptyPdfTextException(super.message, {super.cause});
}

/// Thrown when persisting or deleting document catalog metadata fails.
class DocumentPersistenceException extends AppException {
  const DocumentPersistenceException(super.message, {super.cause});
}

/// Contract for picking, extracting, chunking, embedding, and cataloging study PDFs.
abstract interface class DocumentIngestionRepository {
  Future<String?> pickPdfPath();

  Stream<IngestionProgress> ingestPdf({required String filePath});

  Future<List<StudyDocument>> getAllDocuments();

  Future<void> deleteDocument(String docId);
}
