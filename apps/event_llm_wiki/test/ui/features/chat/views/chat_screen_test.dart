import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/ui/features/agenda/views/talk_detail_screen.dart';
import 'package:event_llm_wiki/ui/features/chat/views/chat_screen.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Talk _talk(String id, {String title = 'On-Device LLMs'}) => Talk(
  id: id,
  title: title,
  abstract: 'A tour of the edge inference landscape.',
  speakers: const [],
  day: ConferenceDay.dayOne,
  track: ConferenceTrack.engineering,
  startTime: DateTime(2026, 11, 10, 9),
  durationMinutes: 45,
);

class _Harness {
  _Harness() {
    agenda = FakeAgendaRepository(seed: [_talk('talk-001')]);
    engine = FakeChatEngineRepository();
    history = FakeChatHistoryRepository();
  }

  late FakeAgendaRepository agenda;
  late FakeChatEngineRepository engine;
  late FakeChatHistoryRepository history;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agendaRepositoryProvider.overrideWithValue(agenda),
          chatEngineRepositoryProvider.overrideWithValue(engine),
          chatHistoryRepositoryProvider.overrideWithValue(history),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('sending a message shows the user text and streams the '
      'assistant reply', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('chatInputField')),
      'Tell me about On-Device LLMs',
    );
    await tester.tap(find.byKey(const ValueKey('chatSendButton')));
    await tester.pump();

    expect(find.text('Tell me about On-Device LLMs'), findsOneWidget);

    harness.engine.emit('It is a great talk.');
    await tester.pump();

    expect(find.textContaining('It is a great talk.'), findsOneWidget);

    await harness.engine.completeStream();
    await tester.pump();
  });

  testWidgets('shows a citation chip under a grounded assistant reply, '
      'navigating to TalkDetailScreen on tap', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.enterText(
      find.byKey(const ValueKey('chatInputField')),
      'Tell me about On-Device LLMs',
    );
    await tester.tap(find.byKey(const ValueKey('chatSendButton')));
    await tester.pump();
    harness.engine.emit('It is great.');
    await harness.engine.completeStream();
    await tester.pumpAndSettle();

    expect(find.text('On-Device LLMs'), findsWidgets);

    await tester.tap(find.text('On-Device LLMs').last);
    await tester.pumpAndSettle();

    expect(find.byType(TalkDetailScreen), findsOneWidget);
  });
}
