import 'package:event_llm_wiki/data/repositories/agenda_repository_impl.dart';
import 'package:event_llm_wiki/data/services/agenda_asset_service.dart';
import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/repositories/agenda_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canned-JSON [AgendaAssetService] fake — no `rootBundle`/real asset
/// bundle involved, per PLAN.md phase 5.
class _FakeAgendaAssetService implements AgendaAssetService {
  _FakeAgendaAssetService(this.json);

  String json;
  int loadCallCount = 0;

  /// If set, [loadAgendaJson] throws this instead of returning [json].
  Object? loadError;

  @override
  Future<String> loadAgendaJson() async {
    loadCallCount++;
    final error = loadError;
    if (error != null) throw error;
    return json;
  }
}

const _validJson = '''
{
  "talks": [
    {
      "id": "talk-001",
      "title": "On-Device LLMs",
      "abstract": "A tour of the edge inference landscape.",
      "speakers": [
        { "name": "Ada Solano", "title": "Principal Engineer", "company": "Nimbus AI" }
      ],
      "day": "dayOne",
      "track": "engineering",
      "startTime": "2026-11-10T09:00:00",
      "durationMinutes": 45
    },
    {
      "id": "talk-002",
      "title": "Designing Trust",
      "abstract": "Citation chips and honest answers.",
      "speakers": [
        { "name": "Sofia Marchetti", "title": "Principal Product Designer" }
      ],
      "day": "dayTwo",
      "track": "productAndDesign",
      "startTime": "2026-11-11T10:00:00",
      "durationMinutes": 30
    }
  ]
}
''';

void main() {
  group('AgendaRepositoryImpl', () {
    test('getAllTalks parses assets/agenda.json into a List<Talk>', () async {
      final repository = AgendaRepositoryImpl(
        agendaAssetService: _FakeAgendaAssetService(_validJson),
      );

      final talks = await repository.getAllTalks();

      expect(talks, hasLength(2));
      final first = talks.firstWhere((t) => t.id == 'talk-001');
      expect(first.title, 'On-Device LLMs');
      expect(first.abstract, 'A tour of the edge inference landscape.');
      expect(first.speakers, hasLength(1));
      expect(first.speakers.single.name, 'Ada Solano');
      expect(first.speakers.single.title, 'Principal Engineer');
      expect(first.speakers.single.company, 'Nimbus AI');
      expect(first.day, ConferenceDay.dayOne);
      expect(first.track, ConferenceTrack.engineering);
      expect(first.startTime, DateTime.parse('2026-11-10T09:00:00'));
      expect(first.durationMinutes, 45);
    });

    test(
      'a speaker with no "company" field parses with a null company',
      () async {
        final repository = AgendaRepositoryImpl(
          agendaAssetService: _FakeAgendaAssetService(_validJson),
        );

        final talks = await repository.getAllTalks();

        final second = talks.firstWhere((t) => t.id == 'talk-002');
        expect(second.speakers.single.company, isNull);
        expect(second.day, ConferenceDay.dayTwo);
        expect(second.track, ConferenceTrack.productAndDesign);
      },
    );

    test('caches the parsed talks — only the first call loads/parses the '
        'asset', () async {
      final assetService = _FakeAgendaAssetService(_validJson);
      final repository = AgendaRepositoryImpl(agendaAssetService: assetService);

      await repository.getAllTalks();
      await repository.getAllTalks();
      await repository.getTalkById('talk-001');

      expect(assetService.loadCallCount, 1);
    });

    test('getTalkById returns the matching talk', () async {
      final repository = AgendaRepositoryImpl(
        agendaAssetService: _FakeAgendaAssetService(_validJson),
      );

      final talk = await repository.getTalkById('talk-002');

      expect(talk.title, 'Designing Trust');
    });

    test(
      'getTalkById throws TalkNotFoundException for an unknown id',
      () async {
        final repository = AgendaRepositoryImpl(
          agendaAssetService: _FakeAgendaAssetService(_validJson),
        );

        expect(
          () => repository.getTalkById('nope'),
          throwsA(isA<TalkNotFoundException>()),
        );
      },
    );

    test('getAllTalks wraps a loader failure in AgendaLoadException', () async {
      final assetService = _FakeAgendaAssetService(_validJson)
        ..loadError = Exception('asset missing');
      final repository = AgendaRepositoryImpl(agendaAssetService: assetService);

      expect(
        () => repository.getAllTalks(),
        throwsA(isA<AgendaLoadException>()),
      );
    });

    test('getAllTalks wraps malformed JSON in AgendaLoadException', () async {
      final repository = AgendaRepositoryImpl(
        agendaAssetService: _FakeAgendaAssetService('not valid json'),
      );

      expect(
        () => repository.getAllTalks(),
        throwsA(isA<AgendaLoadException>()),
      );
    });
  });
}
