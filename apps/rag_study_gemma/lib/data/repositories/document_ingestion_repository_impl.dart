// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:hive/hive.dart';

import '../../core/error/app_exception.dart';
import '../../domain/models/ingestion_progress.dart';
import '../../domain/models/study_document.dart';
import '../../domain/repositories/document_ingestion_repository.dart';
import '../../domain/repositories/rag_index_repository.dart';
import '../../domain/use_cases/chunk_document_use_case.dart';
import '../models/study_document_dto.dart';
import '../services/pdf_extractor_service.dart';
import '../services/pdf_picker_service.dart';

/// Implementation of [DocumentIngestionRepository] coordinating PDF picking,
/// isolate text extraction, sliding-window chunking, `sqlite-vec` embedding,
/// and Hive document catalog persistence.
class DocumentIngestionRepositoryImpl implements DocumentIngestionRepository {
  DocumentIngestionRepositoryImpl({
    required RagIndexRepository ragIndexRepository,
    Box<StudyDocumentDto>? documentsBox,
    Box<StudyDocumentDto>? box,
    PdfPickerService pdfPickerService = const PdfPickerServiceImpl(),
    PdfExtractorService pdfExtractorService = const PdfExtractorServiceImpl(),
    ChunkDocumentUseCase chunkDocumentUseCase = const ChunkDocumentUseCase(),
    DateTime Function()? clock,
  }) : _ragIndexRepository = ragIndexRepository,
       _documentsBox = _requireBox(documentsBox ?? box),
       _pdfPickerService = pdfPickerService,
       _pdfExtractorService = pdfExtractorService,
       _chunkDocumentUseCase = chunkDocumentUseCase,
       _clock = clock ?? DateTime.now;

  final RagIndexRepository _ragIndexRepository;
  final Box<StudyDocumentDto> _documentsBox;
  final PdfPickerService _pdfPickerService;
  final PdfExtractorService _pdfExtractorService;
  final ChunkDocumentUseCase _chunkDocumentUseCase;
  final DateTime Function() _clock;

  static Box<StudyDocumentDto> _requireBox(Box<StudyDocumentDto>? candidate) {
    if (candidate == null) {
      throw ArgumentError.notNull('documentsBox');
    }
    return candidate;
  }

  @override
  Future<String?> pickPdfPath() async {
    try {
      return await _pdfPickerService.pickPdfPath();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        InvalidPdfException('Failed to pick PDF file.', cause: error),
        stackTrace,
      );
    }
  }

  @override
  Stream<IngestionProgress> ingestPdf({required String filePath}) {
    final controller = StreamController<IngestionProgress>();

    Future<void> run() async {
      try {
        final trimmedPath = filePath.trim();
        controller.add(
          const IngestionProgress(
            stage: IngestionStage.validating,
            current: 0,
            total: 1,
            message: 'Validating PDF file header...',
          ),
        );

        if (!trimmedPath.toLowerCase().endsWith('.pdf')) {
          throw InvalidPdfException(
            'Only .pdf files are supported. Selected: $filePath',
          );
        }

        controller.add(
          const IngestionProgress(
            stage: IngestionStage.extracting,
            current: 0,
            total: 1,
            message: 'Extracting text from PDF pages in background isolate...',
          ),
        );

        final extractedPages = await _pdfExtractorService.extractPages(
          trimmedPath,
        );
        final pageCount = extractedPages.length;

        controller.add(
          IngestionProgress(
            stage: IngestionStage.extracting,
            current: pageCount,
            total: pageCount,
            message: 'Extracted $pageCount pages.',
          ),
        );

        final fileName = _extractFileName(trimmedPath);
        final docTitle = _deriveDocumentTitle(fileName);
        final now = _clock();
        final docId = 'doc_${now.microsecondsSinceEpoch}';

        controller.add(
          IngestionProgress(
            stage: IngestionStage.chunking,
            current: 0,
            total: pageCount,
            message: 'Chunking $pageCount pages with sliding window...',
          ),
        );

        final chunks = _chunkDocumentUseCase(
          docId: docId,
          docTitle: docTitle,
          pages: extractedPages,
        );

        if (chunks.isEmpty) {
          throw const EmptyPdfTextException(
            'No indexable text chunks could be produced from this PDF.',
          );
        }

        final totalChunks = chunks.length;
        controller.add(
          IngestionProgress(
            stage: IngestionStage.chunking,
            current: totalChunks,
            total: totalChunks,
            message: 'Created $totalChunks chunks.',
          ),
        );

        controller.add(
          IngestionProgress(
            stage: IngestionStage.embedding,
            current: 0,
            total: totalChunks,
            message: 'Embedding $totalChunks chunks with EmbeddingGemma 2...',
          ),
        );

        await _ragIndexRepository.addChunks(
          chunks,
          onProgress: (current, total) {
            if (!controller.isClosed) {
              controller.add(
                IngestionProgress(
                  stage: IngestionStage.embedding,
                  current: current,
                  total: total,
                  message: 'Indexed $current of $total chunks...',
                ),
              );
            }
          },
        );

        final document = StudyDocument(
          id: docId,
          title: docTitle,
          fileName: fileName,
          filePath: trimmedPath,
          pageCount: pageCount,
          chunkCount: totalChunks,
          indexedAt: now,
        );

        final dto = StudyDocumentDto.fromDomain(
          document,
          chunkIds: [for (final chunk in chunks) chunk.id],
        );
        await _documentsBox.put(document.id, dto);

        controller.add(
          IngestionProgress(
            stage: IngestionStage.completed,
            current: totalChunks,
            total: totalChunks,
            message: 'Indexed ${document.title} ($totalChunks chunks).',
            document: document,
          ),
        );
        await controller.close();
      } catch (error) {
        final message = error is AppException
            ? error.message
            : error.toString();
        if (!controller.isClosed) {
          controller.add(
            IngestionProgress(
              stage: IngestionStage.failed,
              message: message,
              errorMessage: message,
            ),
          );
          await controller.close();
        }
      }
    }

    unawaited(run());
    return controller.stream;
  }

  @override
  Future<List<StudyDocument>> getAllDocuments() async {
    try {
      final docs = _documentsBox.values.map((dto) => dto.toDomain()).toList()
        ..sort((a, b) => b.indexedAt.compareTo(a.indexedAt));
      return docs;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DocumentPersistenceException(
          'Failed to load study documents from Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> deleteDocument(String docId) async {
    try {
      final existingDto = _documentsBox.get(docId);
      final chunkIds = existingDto?.chunkIds ?? const <String>[];
      await _ragIndexRepository.removeDocumentChunks(docId, chunkIds);
      await _documentsBox.delete(docId);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DocumentPersistenceException(
          'Failed to delete study document $docId.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  static String _extractFileName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  static String _deriveDocumentTitle(String fileName) {
    final withoutExt = fileName.replaceAll(
      RegExp(r'\.pdf$', caseSensitive: false),
      '',
    );
    final cleaned = withoutExt
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? fileName : cleaned;
  }
}
