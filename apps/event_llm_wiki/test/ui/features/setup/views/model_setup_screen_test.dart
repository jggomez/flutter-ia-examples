import 'package:event_llm_wiki/domain/models/model_download_status.dart';
import 'package:event_llm_wiki/ui/features/setup/views/model_setup_screen.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeModelDownloadRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: ModelSetupScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows a download CTA when notDownloaded', (tester) async {
    final repository = FakeModelDownloadRepository();

    await _pumpScreen(tester, repository: repository);

    expect(find.byKey(const ValueKey('startDownloadButton')), findsOneWidget);
  });

  testWidgets('tapping the CTA opens the Wi-Fi confirmation dialog and '
      'confirming starts the download and shows progress', (tester) async {
    final repository = FakeModelDownloadRepository()
      ..downloadEvents = const [
        ModelDownloadStatus(
          phase: ModelDownloadPhase.downloading,
          bytesDownloaded: 50,
          totalBytes: 100,
        ),
      ];

    await _pumpScreen(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('confirmModelDownloadDialog')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('confirmDownloadDialogButton')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('cancelling the confirmation dialog does not start download', (
    tester,
  ) async {
    final repository = FakeModelDownloadRepository();

    await _pumpScreen(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cancelDownloadDialogButton')));
    await tester.pumpAndSettle();

    expect(repository.downloadCallCount, 0);
  });

  testWidgets('disables confirm button in dialog when Wi-Fi is not connected', (
    tester,
  ) async {
    final repository = FakeModelDownloadRepository()..wifiConnected = false;

    await _pumpScreen(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('confirmDownloadDialogButton')),
    );
    expect(confirmButton.onPressed, isNull);
    expect(repository.downloadCallCount, 0);
  });

  testWidgets('shows an error and retry CTA when the download fails', (
    tester,
  ) async {
    final repository = FakeModelDownloadRepository()
      ..downloadEvents = const [
        ModelDownloadStatus(
          phase: ModelDownloadPhase.failed,
          errorMessage: 'connection reset',
        ),
      ];

    await _pumpScreen(tester, repository: repository);
    await tester.tap(find.byKey(const ValueKey('startDownloadButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmDownloadDialogButton')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('connection reset'), findsOneWidget);
    expect(find.byKey(const ValueKey('startDownloadButton')), findsOneWidget);
  });
}
