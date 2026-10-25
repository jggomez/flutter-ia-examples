import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/ingestion_progress.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/ui/core/theme/app_theme.dart';
import 'package:rag_study_gemma/ui/core/widgets/ingestion_progress_card.dart';
import 'package:rag_study_gemma/ui/features/chat/view_models/study_chat_view_model.dart';
import 'package:rag_study_gemma/ui/features/library/views/document_library_screen.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeDocumentIngestionRepository fakeIngestionRepo;

  setUp(() {
    fakeIngestionRepo = FakeDocumentIngestionRepository();
  });

  Widget buildSubject({VoidCallback? onNavigateToChat}) {
    return ProviderScope(
      overrides: [
        documentIngestionRepositoryProvider.overrideWithValue(
          fakeIngestionRepo,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: DocumentLibraryScreen(onNavigateToChat: onNavigateToChat),
      ),
    );
  }

  testWidgets('renders empty state explaining 4-step PDF RAG workflow', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.textContaining('Import Study PDF (.pdf only)'), findsWidgets);
    expect(find.byKey(const ValueKey('emptyLibraryState')), findsOneWidget);
  });

  testWidgets(
    'streams 4-stage IngestionProgressCard when importing a PDF and lists indexed document',
    (tester) async {
      final progressController = StreamController<IngestionProgress>();
      fakeIngestionRepo.nextPickedPdfPath = '/tmp/neural_networks.pdf';
      fakeIngestionRepo.customIngestStream = progressController.stream;

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('importPdfButton')));
      await tester.pump();

      progressController.add(
        const IngestionProgress(
          stage: IngestionStage.extracting,
          current: 3,
          total: 10,
          message: 'Extracting page 3 of 10...',
        ),
      );
      await tester.pump();

      expect(find.byType(IngestionProgressCard), findsOneWidget);
      expect(find.textContaining('Extracting page 3 of 10...'), findsOneWidget);
      expect(find.textContaining('3 / 10'), findsOneWidget);

      final doc = StudyDocument(
        id: 'doc_nn',
        title: 'Neural Networks Notes',
        fileName: 'neural_networks.pdf',
        filePath: '/tmp/neural_networks.pdf',
        pageCount: 10,
        chunkCount: 24,
        indexedAt: DateTime.utc(2026, 10, 24),
      );
      fakeIngestionRepo.documents.add(doc);

      progressController.add(
        IngestionProgress(
          stage: IngestionStage.completed,
          current: 24,
          total: 24,
          message: 'Indexed 24 chunks.',
          document: doc,
        ),
      );
      await progressController.close();
      await tester.pumpAndSettle();

      expect(find.byType(IngestionProgressCard), findsNothing);
      expect(find.text('Neural Networks Notes'), findsOneWidget);
      expect(find.textContaining('10 pages'), findsOneWidget);
      expect(find.textContaining('24 chunks in SQLite vec0'), findsOneWidget);
    },
  );

  testWidgets(
    'Ask AI about this PDF selects document filter and invokes onNavigateToChat callback, and delete removes document',
    (tester) async {
      final doc = StudyDocument(
        id: 'doc_calc',
        title: 'Calculus Lecture 1',
        fileName: 'calculus_1.pdf',
        filePath: '/tmp/calculus_1.pdf',
        pageCount: 8,
        chunkCount: 19,
        indexedAt: DateTime.utc(2026, 10, 24),
      );
      fakeIngestionRepo.documents.add(doc);

      var navigatedToChat = false;
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentIngestionRepositoryProvider.overrideWithValue(
              fakeIngestionRepo,
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.lightTheme,
                home: DocumentLibraryScreen(
                  onNavigateToChat: () => navigatedToChat = true,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calculus Lecture 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('askAiButton_doc_calc')));
      await tester.pumpAndSettle();

      expect(navigatedToChat, isTrue);
      expect(container.read(selectedDocumentFilterProvider), 'doc_calc');

      await tester.tap(find.byKey(const ValueKey('deleteDocButton_doc_calc')));
      await tester.pumpAndSettle();

      expect(fakeIngestionRepo.deletedDocIds, contains('doc_calc'));
      expect(find.text('Calculus Lecture 1'), findsNothing);
      expect(container.read(selectedDocumentFilterProvider), isNull);
    },
  );
}
