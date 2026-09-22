import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/speaker.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/ui/features/agenda/views/talk_detail_screen.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

void main() {
  testWidgets('shows the talk title, speakers and abstract', (tester) async {
    final agenda = FakeAgendaRepository(
      seed: [
        Talk(
          id: 'talk-001',
          title: 'On-Device LLMs',
          abstract: 'A tour of the edge inference landscape.',
          speakers: const [
            Speaker(name: 'Ada Solano', title: 'Principal Engineer'),
          ],
          day: ConferenceDay.dayOne,
          track: ConferenceTrack.engineering,
          startTime: DateTime(2026, 11, 10, 9),
          durationMinutes: 45,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [agendaRepositoryProvider.overrideWithValue(agenda)],
        child: const MaterialApp(home: TalkDetailScreen(talkId: 'talk-001')),
      ),
    );
    await tester.pump();

    expect(find.text('On-Device LLMs'), findsOneWidget);
    expect(find.textContaining('Ada Solano'), findsOneWidget);
    expect(
      find.textContaining('A tour of the edge inference landscape.'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error message for an unknown talkId', (tester) async {
    final agenda = FakeAgendaRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [agendaRepositoryProvider.overrideWithValue(agenda)],
        child: const MaterialApp(home: TalkDetailScreen(talkId: 'nope')),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('talkDetailError')), findsOneWidget);
  });
}
