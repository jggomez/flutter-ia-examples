import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/ui/core/theme/app_theme.dart';
import 'package:rag_study_gemma/ui/core/widgets/citation_chip.dart';
import 'package:rag_study_gemma/ui/features/chat/views/study_chat_screen.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeDocumentIngestionRepository fakeIngestionRepo;
  late FakeRagIndexRepository fakeRagRepo;
  late FakeChatEngineRepository fakeChatEngineRepo;
  late FakeChatHistoryRepository fakeChatHistoryRepo;

  setUp(() {
    fakeIngestionRepo = FakeDocumentIngestionRepository();
    fakeRagRepo = FakeRagIndexRepository();
    fakeChatEngineRepo = FakeChatEngineRepository();
    fakeChatHistoryRepo = FakeChatHistoryRepository();

    final doc = StudyDocument(
      id: 'doc_bio',
      title: 'Cell Biology Ch 4',
      fileName: 'cell_biology.pdf',
      filePath: '/tmp/cell_biology.pdf',
      pageCount: 12,
      chunkCount: 30,
      indexedAt: DateTime.utc(2026, 10, 24),
    );
    fakeIngestionRepo.documents.add(doc);

    fakeRagRepo.searchResults = [
      const RetrievedChunk(
        chunk: DocumentChunk(
          id: 'doc_bio_p7_c0',
          docId: 'doc_bio',
          docTitle: 'Cell Biology Ch 4',
          pageNumber: 7,
          chunkIndex: 0,
          content: 'Mitochondria generate most of the chemical energy needed to power the cell biochemical reactions via ATP.',
        ),
        similarityScore: 0.89,
      ),
    ];
    fakeChatEngineRepo.responseTokens = const [
      'Mitochondria produce ',
      'ATP energy [Cell Biology Ch 4, p. 7].',
    ];
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        documentIngestionRepositoryProvider.overrideWithValue(
          fakeIngestionRepo,
        ),
        ragIndexRepositoryProvider.overrideWithValue(fakeRagRepo),
        chatEngineRepositoryProvider.overrideWithValue(fakeChatEngineRepo),
        chatHistoryRepositoryProvider.overrideWithValue(fakeChatHistoryRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const StudyChatScreen(),
      ),
    );
  }

  testWidgets(
    'renders document filter ChoiceChips, study prompt suggestions, and sends grounded question with interactive CitationChip modal',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('All PDFs'), findsOneWidget);
      expect(find.text('Cell Biology Ch 4'), findsOneWidget);
      expect(find.text('Summarize the main concepts'), findsOneWidget);

      await tester.tap(find.text('Cell Biology Ch 4'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chatInputField')),
        'What is the role of mitochondria?',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('chatSendButton')));
      await tester.pumpAndSettle();

      expect(fakeRagRepo.lastFilterDocId, 'doc_bio');
      expect(find.text('What is the role of mitochondria?'), findsOneWidget);
      expect(
        find.textContaining('Mitochondria produce ATP energy'),
        findsOneWidget,
      );
      expect(find.byType(CitationChip), findsOneWidget);
      expect(find.textContaining('Cell Biology Ch 4 · p. 7'), findsOneWidget);

      await tester.tap(find.byType(CitationChip));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Mitochondria generate most of the chemical energy',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('89%'), findsWidgets);
    },
  );

  testWidgets(
    'tapping a prompt suggestion sends message and tapping clear history resets conversation',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Summarize the main concepts'));
      await tester.pumpAndSettle();

      expect(find.text('Summarize the main concepts'), findsOneWidget);
      expect(fakeChatHistoryRepo.messages.length, 2);

      await tester.tap(find.byKey(const ValueKey('clearChatHistoryButton')));
      await tester.pumpAndSettle();

      expect(fakeChatHistoryRepo.clearCallCount, 1);
      expect(fakeChatEngineRepo.resetCallCount, 1);
      expect(find.text('Grounded PDF Study Companion'), findsOneWidget);
    },
  );

  testWidgets(
    'requests topK: 8 candidates for chunk selection and guards against concurrent sendMessage calls while streaming',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chatInputField')),
        'First question',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chatSendButton')));
      await tester.pumpAndSettle();

      expect(fakeRagRepo.lastTopK, 8);
      expect(fakeChatEngineRepo.sentPrompts.length, 1);
    },
  );
}
