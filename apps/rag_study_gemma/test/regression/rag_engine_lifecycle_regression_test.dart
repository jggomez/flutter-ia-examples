import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/app.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/ui/features/chat/view_models/study_chat_view_model.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
    'studyChatViewModelProvider is non-autoDispose: switching between PDF Library and Study Chat tabs does NOT re-initialize RagIndex or ChatEngine',
    (tester) async {
      final fakeDownloadRepo = FakeModelDownloadRepository()
        ..modelsReady = true;
      final fakeIngestionRepo = FakeDocumentIngestionRepository();
      final fakeRagRepo = FakeRagIndexRepository();
      final fakeChatEngineRepo = FakeChatEngineRepository();
      final fakeChatHistoryRepo = FakeChatHistoryRepository();

      final docA = StudyDocument(
        id: 'doc_a',
        title: 'Algorithms & Data Structures',
        fileName: 'algorithms.pdf',
        filePath: '/tmp/algorithms.pdf',
        pageCount: 15,
        chunkCount: 40,
        indexedAt: DateTime.utc(2026, 10, 24),
      );
      final docB = StudyDocument(
        id: 'doc_b',
        title: 'Operating Systems Concepts',
        fileName: 'os_concepts.pdf',
        filePath: '/tmp/os_concepts.pdf',
        pageCount: 20,
        chunkCount: 52,
        indexedAt: DateTime.utc(2026, 10, 24),
      );
      fakeIngestionRepo.documents.addAll([docA, docB]);

      fakeRagRepo.searchResults = [
        const RetrievedChunk(
          chunk: DocumentChunk(
            id: 'doc_a_p4_c1',
            docId: 'doc_a',
            docTitle: 'Algorithms & Data Structures',
            pageNumber: 4,
            chunkIndex: 1,
            content: 'Dijkstra algorithm finds shortest paths from source.',
          ),
          similarityScore: 0.92,
        ),
        const RetrievedChunk(
          chunk: DocumentChunk(
            id: 'doc_b_p9_c0',
            docId: 'doc_b',
            docTitle: 'Operating Systems Concepts',
            pageNumber: 9,
            chunkIndex: 0,
            content: 'Virtual memory maps virtual addresses to physical pages.',
          ),
          similarityScore: 0.85,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelDownloadRepositoryProvider.overrideWithValue(fakeDownloadRepo),
            documentIngestionRepositoryProvider.overrideWithValue(
              fakeIngestionRepo,
            ),
            ragIndexRepositoryProvider.overrideWithValue(fakeRagRepo),
            chatEngineRepositoryProvider.overrideWithValue(fakeChatEngineRepo),
            chatHistoryRepositoryProvider.overrideWithValue(
              fakeChatHistoryRepo,
            ),
          ],
          child: const StudyGemmaApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on PDF Library tab; tap "Ask AI about this PDF" on doc_a
      await tester.tap(find.byKey(const ValueKey('askAiButton_doc_a')));
      await tester.pumpAndSettle();

      expect(fakeRagRepo.initializeCallCount, 1);
      expect(fakeChatEngineRepo.initializeCallCount, 1);

      // Send a question while filtered to doc_a
      await tester.enterText(
        find.byKey(const ValueKey('chatInputField')),
        'How does Dijkstra work?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chatSendButton')));
      await tester.pumpAndSettle();

      expect(fakeRagRepo.lastFilterDocId, 'doc_a');
      expect(
        find.textContaining('Algorithms & Data Structures · p. 4'),
        findsOneWidget,
      );

      // Switch back to PDF Library tab
      await tester.tap(find.text('PDF Library'));
      await tester.pumpAndSettle();

      // Switch back to Study Chat tab
      await tester.tap(find.text('Study Chat'));
      await tester.pumpAndSettle();

      // Engine and RagIndex MUST NOT have been re-initialized!
      expect(fakeRagRepo.initializeCallCount, 1);
      expect(fakeChatEngineRepo.initializeCallCount, 1);
      expect(fakeRagRepo.disposeCallCount, 0);
      expect(fakeChatEngineRepo.disposeCallCount, 0);

      // Conversation state remains warm in memory
      expect(find.text('How does Dijkstra work?'), findsOneWidget);
      expect(
        find.textContaining('Algorithms & Data Structures · p. 4'),
        findsOneWidget,
      );

      // Verify provider is not autoDispose at container level
      final element = tester.element(find.byType(StudyGemmaApp));
      final container = ProviderScope.containerOf(element);
      final messages = await container.read(studyChatViewModelProvider.future);
      expect(messages.length, 2);
      expect(messages.last.citations.single.pageNumber, 4);
    },
  );
}
