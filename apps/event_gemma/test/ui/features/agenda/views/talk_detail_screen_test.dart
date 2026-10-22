import 'package:event_gemma/domain/models/conference_day.dart';
import 'package:event_gemma/domain/models/conference_track.dart';
import 'package:event_gemma/domain/models/speaker.dart';
import 'package:event_gemma/domain/models/talk.dart';
import 'package:event_gemma/ui/features/agenda/views/talk_detail_screen.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
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

  testWidgets(
    'renders hero header, info ribbon, speaker profile, and Ask AI CTA',
    (tester) async {
      final agenda = FakeAgendaRepository(
        seed: [
          Talk(
            id: 'talk-001',
            title: 'On-Device LLMs',
            abstract: 'A tour of the edge inference landscape.',
            speakers: const [
              Speaker(
                name: 'Ada Solano',
                title: 'Principal Engineer',
                company: 'Nimbus AI',
              ),
            ],
            day: ConferenceDay.dayOne,
            track: ConferenceTrack.engineering,
            startTime: DateTime(2026, 11, 10, 9, 0),
            durationMinutes: 45,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agendaRepositoryProvider.overrideWithValue(agenda),
            chatEngineRepositoryProvider.overrideWithValue(
              FakeChatEngineRepository(),
            ),
            chatHistoryRepositoryProvider.overrideWithValue(
              FakeChatHistoryRepository(),
            ),
            modelDownloadRepositoryProvider.overrideWithValue(
              FakeModelDownloadRepository(),
            ),
          ],
          child: const MaterialApp(home: TalkDetailScreen(talkId: 'talk-001')),
        ),
      );
      await tester.pump();

      // Hero title
      expect(find.text('On-Device LLMs'), findsOneWidget);

      // Info ribbon: Day, Track, Time
      expect(find.textContaining('Day 1'), findsOneWidget);
      expect(find.text('Engineering'), findsOneWidget);
      expect(find.textContaining('09:00'), findsOneWidget);
      expect(find.textContaining('45 min'), findsOneWidget);

      // Speaker card
      expect(find.text('AS'), findsOneWidget); // Initials
      expect(find.text('Ada Solano'), findsOneWidget);
      expect(find.textContaining('Principal Engineer'), findsOneWidget);
      expect(find.textContaining('Nimbus AI'), findsOneWidget);

      // "Ask AI about this talk" button
      expect(find.text('Ask AI about this talk'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

      // Tap "Ask AI about this talk"
      await tester.tap(find.text('Ask AI about this talk'));
      await tester.pumpAndSettle();

      // Verify it navigated
      expect(find.byType(TalkDetailScreen), findsNothing);
    },
  );
}
