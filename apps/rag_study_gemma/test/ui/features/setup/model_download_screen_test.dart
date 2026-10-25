import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/domain/models/model_download_status.dart';
import 'package:rag_study_gemma/ui/core/theme/app_theme.dart';
import 'package:rag_study_gemma/ui/features/setup/views/model_download_screen.dart';
import 'package:rag_study_gemma/ui/providers/repository_providers.dart';

import '../../../support/fakes.dart';

void main() {
  late FakeModelDownloadRepository fakeDownloadRepo;

  setUp(() {
    fakeDownloadRepo = FakeModelDownloadRepository()..modelsReady = false;
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(fakeDownloadRepo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const ModelDownloadScreen(),
      ),
    );
  }

  testWidgets(
    'renders dual-model specs, Wi-Fi badge, and optional HF token field when not downloaded',
    (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.textContaining('EmbeddingGemma 2'), findsWidgets);
      expect(find.textContaining('157 MB'), findsWidgets);
      expect(find.textContaining('Gemma 4 E2B IT'), findsWidgets);
      expect(find.textContaining('2.58 GB'), findsWidgets);
      expect(find.textContaining('~2.74 GB'), findsWidgets);
      expect(find.textContaining('Wi-Fi'), findsWidgets);
      expect(find.byKey(const ValueKey('hfTokenTextField')), findsOneWidget);
      expect(find.byKey(const ValueKey('startDownloadButton')), findsOneWidget);
    },
  );

  testWidgets(
    'opens confirmation dialog, passes HF token, and streams download stages to ready',
    (tester) async {
      final controller = StreamController<ModelDownloadStatus>();
      fakeDownloadRepo.customDownloadStream = controller.stream;

      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('hfTokenTextField')),
        'hf_test_token_123',
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('startDownloadButton')),
      );
      await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('confirmModelDownloadDialog')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('confirmDownloadDialogButton')),
      );
      await tester.pump();

      expect(fakeDownloadRepo.lastHfToken, 'hf_test_token_123');

      controller.add(
        const ModelDownloadStatus(
          phase: ModelDownloadPhase.downloadingEmbedding,
          bytesReceived: 80 * 1024 * 1024,
          totalBytes: 157 * 1024 * 1024,
          currentModelName: 'EmbeddingGemma 2 (270M)',
        ),
      );
      await tester.pump();

      expect(find.textContaining('EmbeddingGemma 2 (270M)'), findsWidgets);
      expect(find.textContaining('51%'), findsOneWidget);

      controller.add(
        const ModelDownloadStatus(
          phase: ModelDownloadPhase.downloadingLlm,
          bytesReceived: 1290 * 1024 * 1024,
          totalBytes: 2580 * 1024 * 1024,
          currentModelName: 'Gemma 4 E2B IT',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Gemma 4 E2B IT'), findsWidgets);
      expect(find.textContaining('50%'), findsOneWidget);

      controller.add(
        const ModelDownloadStatus(
          phase: ModelDownloadPhase.ready,
          bytesReceived: 2580 * 1024 * 1024,
          totalBytes: 2580 * 1024 * 1024,
          currentModelName: 'Gemma 4 E2B IT',
        ),
      );
      await controller.close();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('renders error message and retry button when download fails', (
    tester,
  ) async {
    fakeDownloadRepo.wifiConnected = false;

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('startDownloadButton')),
    );
    await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('confirmModelDownloadDialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirmDownloadDialogButton')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Active Wi-Fi connection'), findsOneWidget);
    expect(find.textContaining('Retry'), findsOneWidget);
  });
}
