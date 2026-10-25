import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rag_study_gemma/data/local/hive_boxes.dart';
import 'package:rag_study_gemma/data/models/study_document_dto.dart';
import 'package:rag_study_gemma/data/repositories/document_ingestion_repository_impl.dart';
import 'package:rag_study_gemma/data/services/pdf_extractor_service.dart';
import 'package:rag_study_gemma/data/services/pdf_picker_service.dart';
import 'package:rag_study_gemma/domain/models/extracted_pdf_page.dart';
import 'package:rag_study_gemma/domain/models/ingestion_progress.dart';
import 'package:rag_study_gemma/domain/repositories/document_ingestion_repository.dart';

import '../../support/fakes.dart';

class _FakePdfPickerService implements PdfPickerService {
  String? nextPath;
  Object? error;

  @override
  Future<String?> pickPdfPath() async {
    if (error != null) throw error!;
    return nextPath;
  }
}

class _FakePdfExtractorService implements PdfExtractorService {
  List<ExtractedPdfPage> pages = const [
    ExtractedPdfPage(
      pageNumber: 1,
      text: 'Backpropagation computes gradients layer by layer using the chain rule.',
    ),
    ExtractedPdfPage(
      pageNumber: 2,
      text:
          'Stochastic gradient descent updates parameters using mini-batches.',
    ),
  ];
  Object? error;

  @override
  Future<List<ExtractedPdfPage>> extractPages(String filePath) async {
    if (error != null) throw error!;
    return pages;
  }
}

void main() {
  group('DocumentIngestionRepositoryImpl', () {
    late Directory tempDir;
    late Box<StudyDocumentDto> box;
    late _FakePdfPickerService fakePicker;
    late _FakePdfExtractorService fakeExtractor;
    late FakeRagIndexRepository fakeRagIndex;
    late DocumentIngestionRepositoryImpl repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('doc_ingest_repo_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(HiveTypeIds.studyDocumentDto)) {
        Hive.registerAdapter(StudyDocumentDtoAdapter());
      }
      box = await Hive.openBox<StudyDocumentDto>(HiveBoxes.documents);
      fakePicker = _FakePdfPickerService();
      fakeExtractor = _FakePdfExtractorService();
      fakeRagIndex = FakeRagIndexRepository();
      repository = DocumentIngestionRepositoryImpl(
        pdfPickerService: fakePicker,
        pdfExtractorService: fakeExtractor,
        ragIndexRepository: fakeRagIndex,
        documentsBox: box,
      );
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('pickPdfPath returns path from PdfPickerService', () async {
      fakePicker.nextPath = '/storage/textbook.pdf';
      expect(await repository.pickPdfPath(), equals('/storage/textbook.pdf'));
    });

    test('ingestPdf streams validating -> extracting -> chunking -> embedding -> completed and saves to Hive', () async {
      final events = await repository
          .ingestPdf(filePath: '/storage/Neural_Networks_101.pdf')
          .toList();

      final stages = events.map((e) => e.stage).toList();
      expect(stages, contains(IngestionStage.validating));
      expect(stages, contains(IngestionStage.extracting));
      expect(stages, contains(IngestionStage.chunking));
      expect(stages, contains(IngestionStage.embedding));
      expect(stages.last, equals(IngestionStage.completed));

      final completedEvent = events.last;
      expect(completedEvent.document, isNotNull);
      expect(completedEvent.document!.title, equals('Neural Networks 101'));
      expect(
        completedEvent.document!.fileName,
        equals('Neural_Networks_101.pdf'),
      );
      expect(completedEvent.document!.pageCount, equals(2));
      expect(completedEvent.document!.chunkCount, equals(2));

      expect(fakeRagIndex.indexedChunks, hasLength(2));

      final docs = await repository.getAllDocuments();
      expect(docs, hasLength(1));
      expect(docs.first.id, equals(completedEvent.document!.id));

      final persistedDto = box.get(completedEvent.document!.id);
      expect(persistedDto, isNotNull);
      expect(persistedDto!.chunkIds, hasLength(2));
    });

    test('ingestPdf emits failed stage when PdfExtractorService throws InvalidPdfException', () async {
      fakeExtractor.error = const InvalidPdfException('Missing %PDF- header');

      final events = await repository
          .ingestPdf(filePath: '/storage/broken.pdf')
          .toList();

      expect(events.last.stage, equals(IngestionStage.failed));
      expect(events.last.errorMessage, contains('Missing %PDF- header'));
      expect(box.values, isEmpty);
    });

    test('deleteDocument removes chunks from RagIndexRepository and deletes entry from Hive', () async {
      final events = await repository
          .ingestPdf(filePath: '/storage/Lecture_Notes.pdf')
          .toList();
      final doc = events.last.document!;
      expect(fakeRagIndex.indexedChunks, isNotEmpty);
      expect(box.containsKey(doc.id), isTrue);

      await repository.deleteDocument(doc.id);

      expect(fakeRagIndex.indexedChunks, isEmpty);
      expect(box.containsKey(doc.id), isFalse);
      expect(await repository.getAllDocuments(), isEmpty);
    });
  });
}
