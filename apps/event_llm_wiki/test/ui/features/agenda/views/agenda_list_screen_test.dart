import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/domain/repositories/agenda_repository.dart';
import 'package:event_llm_wiki/ui/features/agenda/views/agenda_list_screen.dart';
import 'package:event_llm_wiki/ui/features/agenda/views/talk_detail_screen.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
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
}
