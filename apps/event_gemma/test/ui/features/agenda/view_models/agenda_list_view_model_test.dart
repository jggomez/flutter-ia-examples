import 'package:event_gemma/domain/models/conference_day.dart';
import 'package:event_gemma/domain/models/conference_track.dart';
import 'package:event_gemma/domain/models/talk.dart';
import 'package:event_gemma/domain/repositories/agenda_repository.dart';
import 'package:event_gemma/ui/features/agenda/view_models/agenda_list_view_model.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Talk _talk(String id, {DateTime? startTime}) => Talk(
  id: id,
  title: 'Talk $id',
  abstract: 'abstract',
  speakers: const [],
  day: ConferenceDay.dayOne,
  track: ConferenceTrack.engineering,
  startTime: startTime ?? DateTime(2026, 11, 10, 9),
  durationMinutes: 30,
);

void main() {
  group('AgendaListViewModel', () {
    test('build() returns talks sorted chronologically by startTime', () async {
      final repository = FakeAgendaRepository(
        seed: [
          _talk('c', startTime: DateTime(2026, 11, 10, 14)),
          _talk('a', startTime: DateTime(2026, 11, 10, 9)),
          _talk('b', startTime: DateTime(2026, 11, 10, 11)),
        ],
      );
      final container = ProviderContainer(
        overrides: [agendaRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final talks = await container.read(agendaListViewModelProvider.future);

      expect(talks.map((t) => t.id).toList(), ['a', 'b', 'c']);
    });

    test('surfaces an AgendaLoadException as AsyncError', () async {
      final repository = FakeAgendaRepository()
        ..getAllTalksError = const AgendaLoadException('boom');
      final container = ProviderContainer(
        overrides: [agendaRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(agendaListViewModelProvider.future),
        throwsA(isA<AgendaLoadException>()),
      );
    });
  });
}
