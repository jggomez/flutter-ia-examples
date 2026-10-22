import 'package:event_gemma/domain/models/conference_day.dart';
import 'package:event_gemma/domain/models/conference_track.dart';
import 'package:event_gemma/domain/models/speaker.dart';
import 'package:event_gemma/domain/models/talk.dart';
import 'package:event_gemma/domain/repositories/agenda_repository.dart';
import 'package:event_gemma/ui/features/agenda/views/agenda_list_screen.dart';
import 'package:event_gemma/ui/features/agenda/views/talk_detail_screen.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Talk _talk(
  String id, {
  String title = 'A talk',
  ConferenceDay day = ConferenceDay.dayOne,
  ConferenceTrack track = ConferenceTrack.engineering,
  DateTime? startTime,
}) => Talk(
  id: id,
  title: title,
  abstract: 'abstract',
  speakers: const [],
  day: day,
  track: track,
  startTime: startTime ?? DateTime(2026, 11, 10, 9),
  durationMinutes: 30,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeAgendaRepository agenda,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [agendaRepositoryProvider.overrideWithValue(agenda)],
      child: const MaterialApp(home: AgendaListScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows a loading indicator, then the talk list', (tester) async {
    final agenda = FakeAgendaRepository(
      seed: [_talk('talk-001', title: 'On-Device LLMs')],
    );

    await _pumpScreen(tester, agenda: agenda);

    expect(find.text('On-Device LLMs'), findsOneWidget);
  });

  testWidgets('shows an error message when the agenda fails to load', (
    tester,
  ) async {
    final agenda = FakeAgendaRepository()
      ..getAllTalksError = const AgendaLoadException('boom');

    await _pumpScreen(tester, agenda: agenda);

    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('tapping a talk navigates to TalkDetailScreen for its id', (
    tester,
  ) async {
    final agenda = FakeAgendaRepository(
      seed: [_talk('talk-001', title: 'On-Device LLMs')],
    );

    await _pumpScreen(tester, agenda: agenda);
    await tester.tap(find.text('On-Device LLMs'));
    await tester.pumpAndSettle();

    expect(find.byType(TalkDetailScreen), findsOneWidget);
  });

  testWidgets('renders Day filter chips and filters talks by selected day', (
    tester,
  ) async {
    final agenda = FakeAgendaRepository(
      seed: [
        _talk('talk-001', title: 'Day 1 Talk', day: ConferenceDay.dayOne),
        _talk('talk-002', title: 'Day 2 Talk', day: ConferenceDay.dayTwo),
      ],
    );

    await _pumpScreen(tester, agenda: agenda);

    expect(find.text('All Days'), findsOneWidget);
    expect(find.textContaining('Day 1'), findsWidgets);
    expect(find.textContaining('Day 2'), findsWidgets);
    expect(find.text('Day 1 Talk'), findsOneWidget);
    expect(find.text('Day 2 Talk'), findsOneWidget);

    // Tap Day 1 filter chip
    await tester.tap(find.textContaining('Day 1').first);
    await tester.pumpAndSettle();

    expect(find.text('Day 1 Talk'), findsOneWidget);
    expect(find.text('Day 2 Talk'), findsNothing);

    // Tap All Days filter chip
    await tester.tap(find.text('All Days'));
    await tester.pumpAndSettle();

    expect(find.text('Day 1 Talk'), findsOneWidget);
    expect(find.text('Day 2 Talk'), findsOneWidget);
  });

  testWidgets('renders track badges, formatted time, and speaker initials', (
    tester,
  ) async {
    final talk = Talk(
      id: 'talk-rich',
      title: 'Advanced LiteRT Optimization',
      abstract: 'Abstract here',
      speakers: const [
        Speaker(
          name: 'Marcus Webb',
          title: 'Staff Engineer',
          company: 'Google',
        ),
      ],
      day: ConferenceDay.dayOne,
      track: ConferenceTrack.engineering,
      startTime: DateTime(2026, 11, 10, 9, 30),
      durationMinutes: 45,
    );
    final agenda = FakeAgendaRepository(seed: [talk]);

    await _pumpScreen(tester, agenda: agenda);

    expect(
      find.byKey(const ValueKey('talkListItem_talk-rich')),
      findsOneWidget,
    );
    expect(find.text('Advanced LiteRT Optimization'), findsOneWidget);
    expect(find.text('Engineering'), findsWidgets);
    expect(find.text('MW'), findsOneWidget); // Initials
    expect(find.textContaining('Marcus Webb'), findsOneWidget);
    expect(find.textContaining('09:30'), findsOneWidget);
  });
}
