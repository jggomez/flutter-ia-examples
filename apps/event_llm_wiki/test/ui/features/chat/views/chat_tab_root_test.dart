import 'package:event_llm_wiki/domain/models/model_download_status.dart';
import 'package:event_llm_wiki/ui/features/chat/views/chat_screen.dart';
import 'package:event_llm_wiki/ui/features/chat/views/chat_tab_root.dart';
import 'package:event_llm_wiki/ui/features/setup/views/model_setup_screen.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Future<void> _pumpRoot(
  WidgetTester tester, {
  required FakeModelDownloadRepository modelDownload,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        modelDownloadRepositoryProvider.overrideWithValue(modelDownload),
        agendaRepositoryProvider.overrideWithValue(FakeAgendaRepository()),
        chatEngineRepositoryProvider.overrideWithValue(
          FakeChatEngineRepository(),
        ),
        chatHistoryRepositoryProvider.overrideWithValue(
          FakeChatHistoryRepository(),
        ),
      ],
      child: const MaterialApp(home: ChatTabRoot()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows ModelSetupScreen while the model is not ready', (
    tester,
  ) async {
    await _pumpRoot(tester, modelDownload: FakeModelDownloadRepository());

    expect(find.byType(ModelSetupScreen), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('shows ChatScreen once the model is ready', (tester) async {
    final modelDownload = FakeModelDownloadRepository()
      ..localStatus = const ModelDownloadStatus(
        phase: ModelDownloadPhase.ready,
      );

    await _pumpRoot(tester, modelDownload: modelDownload);
    await tester.pump();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(ModelSetupScreen), findsNothing);
  });
}
