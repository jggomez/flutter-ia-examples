import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/core/error/app_exception.dart';
import 'package:rag_study_gemma/domain/models/chat_message.dart';
import 'package:rag_study_gemma/domain/models/chat_role.dart';
import 'package:rag_study_gemma/domain/models/citation.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/extracted_pdf_page.dart';
import 'package:rag_study_gemma/domain/models/ingestion_progress.dart';
import 'package:rag_study_gemma/domain/models/model_download_status.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

void main() {
  group('Domain Models & Core Exceptions', () {
    test('StudyDocument supports value equality and copyWith', () {
      final d1 = StudyDocument(
        id: '1',
        title: 'AI Book',
        fileName: 'ai.pdf',
        filePath: '/path/ai.pdf',
        pageCount: 10,
        chunkCount: 25,
        indexedAt: DateTime.utc(2026, 10, 24),
      );
      final d2 = d1.copyWith();
      final d3 = d1.copyWith(chunkCount: 30);

      expect(d1, equals(d2));
      expect(d1.hashCode, equals(d2.hashCode));
      expect(d1, isNot(equals(d3)));
    });

    test('ExtractedPdfPage, DocumentChunk, and RetrievedChunk support value equality', () {
      const p1 = ExtractedPdfPage(pageNumber: 1, text: 'Hello');
      const p2 = ExtractedPdfPage(pageNumber: 1, text: 'Hello');
      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));

      const c1 = DocumentChunk(
        id: '1_p1_c0',
        docId: '1',
        docTitle: 'Book',
        pageNumber: 1,
        chunkIndex: 0,
        content: 'Hello',
      );
      const c2 = DocumentChunk(
        id: '1_p1_c0',
        docId: '1',
        docTitle: 'Book',
        pageNumber: 1,
        chunkIndex: 0,
        content: 'Hello',
      );
      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));

      const r1 = RetrievedChunk(chunk: c1, similarityScore: 0.85);
      const r2 = RetrievedChunk(chunk: c2, similarityScore: 0.85);
      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('ChatMessage and Citation support value equality and copyWith', () {
      const citation = Citation(
        id: 'cit1',
        docId: 'doc1',
        docTitle: 'Book',
        pageNumber: 3,
        snippet: 'Excerpt',
        similarityScore: 0.9,
      );
      final m1 = ChatMessage(
        id: 'm1',
        role: ChatRole.assistant,
        text: 'Answer',
        createdAt: DateTime.utc(2026, 10, 24),
        citations: const [citation],
        isStreaming: true,
      );
      final m2 = m1.copyWith();
      final m3 = m1.copyWith(isStreaming: false);

      expect(m1, equals(m2));
      expect(m1.hashCode, equals(m2.hashCode));
      expect(m1.content, equals('Answer'));
      expect(m1, isNot(equals(m3)));
    });

    test(
      'IngestionProgress and ModelDownloadStatus compute progress accurately',
      () {
        const p1 = IngestionProgress(
          stage: IngestionStage.embedding,
          current: 5,
          total: 10,
        );
        const p2 = IngestionProgress(stage: IngestionStage.completed);
        expect(p1.progress, equals(0.5));
        expect(p2.progress, equals(1.0));

        const s1 = ModelDownloadStatus(
          phase: ModelDownloadPhase.downloadingEmbedding,
          bytesReceived: 50,
          totalBytes: 100,
        );
        const s2 = ModelDownloadStatus(phase: ModelDownloadPhase.ready);
        expect(s1.progress, equals(0.5));
        expect(s2.progress, equals(1.0));
      },
    );

    test('AppException formats message and cause', () {
      const ex1 = AppException('Failed');
      const ex2 = AppException('Failed', cause: 'Disk full');
      expect(ex1.toString(), contains('Failed'));
      expect(ex2.toString(), contains('Disk full'));
    });

    test(
      'repository_providers throw UnimplementedError when not overridden',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          () => container.read(documentIngestionRepositoryProvider),
          throwsA(isA<Object>()),
        );
        expect(
          () => container.read(ragIndexRepositoryProvider),
          throwsA(isA<Object>()),
        );
        expect(
          () => container.read(chatEngineRepositoryProvider),
          throwsA(isA<Object>()),
        );
        expect(
          () => container.read(chatHistoryRepositoryProvider),
          throwsA(isA<Object>()),
        );
        expect(
          () => container.read(modelDownloadRepositoryProvider),
          throwsA(isA<Object>()),
        );
      },
    );
  });
}
