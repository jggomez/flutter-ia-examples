import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/app.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'StudyGemmaApp gates on ModelDownloadScreen when models are not ready and transitions to 2-tab shell when ready',
    (WidgetTester tester) async {
      final fakeDownloadRepo = FakeModelDownloadRepository()
        ..modelsReady = false;
      final fakeIngestionRepo = FakeDocumentIngestionRepository();
      final fakeRagRepo = FakeRagIndexRepository();
      final fakeChatEngineRepo = FakeChatEngineRepository();
      final fakeChatHistoryRepo = FakeChatHistoryRepository();

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

      // Should show ModelDownloadScreen gate first
      expect(find.textContaining('EmbeddingGemma 2'), findsWidgets);
      expect(find.byKey(const ValueKey('startDownloadButton')), findsOneWidget);

      // Start download and confirm dialog
      await tester.ensureVisible(
        find.byKey(const ValueKey('startDownloadButton')),
      );
      await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('confirmDownloadDialogButton')),
      );
      await tester.pumpAndSettle();

      // Now transitions to the 2-tab home shell
      expect(find.text('PDF Library'), findsOneWidget);
      expect(find.text('Study Chat'), findsOneWidget);
    },
  );
}
