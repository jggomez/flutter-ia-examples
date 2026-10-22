import 'package:event_gemma/domain/models/conference_day.dart';
import 'package:event_gemma/domain/models/conference_track.dart';
import 'package:event_gemma/domain/models/talk.dart';
import 'package:event_gemma/domain/repositories/agenda_repository.dart';
import 'package:event_gemma/ui/features/agenda/view_models/talk_detail_view_model.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

Talk _talk(String id, {String title = 'A talk'}) => Talk(
  id: id,
  title: title,
  abstract: 'abstract',
  speakers: const [],
  day: ConferenceDay.dayOne,
  track: ConferenceTrack.engineering,
  startTime: DateTime(2026, 11, 10, 9),
  durationMinutes: 30,
);

void main() {
  group('TalkDetailViewModel', () {
    test('build() returns the talk matching the family argument', () async {
      final repository = FakeAgendaRepository(
        seed: [
          _talk('talk-001', title: 'On-Device LLMs'),
          _talk('talk-002'),
        ],
      );
      final container = ProviderContainer(
        overrides: [agendaRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final talk = await container.read(
        talkDetailViewModelProvider('talk-001').future,
      );

      expect(talk.title, 'On-Device LLMs');
    });

    test(
      'surfaces TalkNotFoundException as AsyncError for an unknown id',
      () async {
        final repository = FakeAgendaRepository(seed: [_talk('talk-001')]);
        final container = ProviderContainer(
          overrides: [agendaRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(talkDetailViewModelProvider('nope').future),
          throwsA(isA<TalkNotFoundException>()),
        );
      },
    );

    test('each talkId gets its own independent provider instance', () async {
      final repository = FakeAgendaRepository(
        seed: [
          _talk('talk-001', title: 'First'),
          _talk('talk-002', title: 'Second'),
        ],
      );
      final container = ProviderContainer(
        overrides: [agendaRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final first = await container.read(
        talkDetailViewModelProvider('talk-001').future,
      );
      final second = await container.read(
        talkDetailViewModelProvider('talk-002').future,
      );

      expect(first.title, 'First');
      expect(second.title, 'Second');
    });
  });
}
