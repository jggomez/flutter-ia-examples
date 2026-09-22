import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/speaker.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/domain/use_cases/retrieve_relevant_talks_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exhaustive synthetic fixtures for
/// `doc/adr/0002-rag-lexical-retrieval.md`'s weighted lexical scorer:
/// title x3, speaker x2, track/day x1, abstract x1; drop zero-score talks;
/// sort by score desc, then titleMatchCount desc, then startTime asc, then
/// id asc; top 3; a no-match query returns an empty list.
Talk _talk({
  required String id,
  String title = 'Untitled talk',
  String abstract = 'Nothing of particular interest here.',
  List<Speaker> speakers = const [],
  ConferenceDay day = ConferenceDay.dayOne,
  ConferenceTrack track = ConferenceTrack.engineering,
  DateTime? startTime,
  int durationMinutes = 30,
}) => Talk(
  id: id,
  title: title,
  abstract: abstract,
  speakers: speakers,
  day: day,
  track: track,
  startTime: startTime ?? DateTime(2026, 11, 10, 9),
  durationMinutes: durationMinutes,
);

const _useCase = RetrieveRelevantTalksUseCase();

void main() {
  group('RetrieveRelevantTalksUseCase', () {
    test('scores a title token match x3', () {
      final talks = [_talk(id: 'talk-001', title: 'Quantization in Practice')];

      final result = _useCase(query: 'quantization', talks: talks);

      expect(result, hasLength(1));
      expect(result.single.score, 3);
      expect(result.single.titleMatchCount, 1);
    });

    test('scores a speaker-name token match x2', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Something unrelated',
          speakers: const [Speaker(name: 'Ada Solano', title: 'Engineer')],
        ),
      ];

      final result = _useCase(query: 'Solano', talks: talks);

      expect(result.single.score, 2);
      expect(result.single.titleMatchCount, 0);
    });

    test('scores a track/day label token match x1', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Something unrelated',
          track: ConferenceTrack.engineering,
        ),
      ];

      final result = _useCase(query: 'engineering', talks: talks);

      expect(result.single.score, 1);
    });

    test('day label token ("Day 1"/"Day 2") also matches at weight x1', () {
      final talks = [
        _talk(id: 'talk-001', title: 'Unrelated', day: ConferenceDay.dayTwo),
      ];

      final result = _useCase(query: 'day', talks: talks);

      expect(result.single.score, 1);
    });

    test('scores an abstract token match x1', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Unrelated title',
          abstract: 'A deep dive into on-device XNNPACK kernels.',
        ),
      ];

      final result = _useCase(query: 'xnnpack', talks: talks);

      expect(result.single.score, 1);
    });

    test('a single query token matching multiple fields accumulates weight '
        'across each matched field independently', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Engineering excellence',
          abstract: 'A talk about engineering culture.',
          track: ConferenceTrack.engineering,
        ),
      ];

      final result = _useCase(query: 'engineering', talks: talks);

      // title x3 + track label x1 + abstract x1 = 5.
      expect(result.single.score, 5);
      expect(result.single.titleMatchCount, 1);
    });

    test('multi-token query sums weighted matches across tokens', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Quantization in Practice',
          speakers: const [Speaker(name: 'Marcus Webb', title: 'Engineer')],
          abstract: 'Benchmarks of dynamic_int4 quantization on mobile.',
        ),
      ];

      final result = _useCase(query: 'quantization Marcus', talks: talks);

      // "quantization": title x3 + abstract x1 = 4. "marcus": speaker x2.
      expect(result.single.score, 6);
      expect(result.single.titleMatchCount, 1);
    });

    test('query is normalized: lowercased and stripped of punctuation', () {
      final talks = [_talk(id: 'talk-001', title: 'Quantization')];

      final result = _useCase(query: 'QUANTIZATION?!', talks: talks);

      expect(result.single.score, 3);
    });

    test('talk fields are matched case-insensitively too', () {
      final talks = [_talk(id: 'talk-001', title: 'QUANTIZATION')];

      final result = _useCase(query: 'quantization', talks: talks);

      expect(result.single.score, 3);
    });

    test('common stopwords are dropped from the query and never match', () {
      final talks = [_talk(id: 'talk-001', title: 'The Talk About Is')];

      // Every query token here is a stopword ("what", "is", "the") that
      // should be dropped before scoring, so nothing should match even
      // though "the"/"is" appear verbatim in the (contrived) title.
      final result = _useCase(query: 'what is the', talks: talks);

      expect(result, isEmpty);
    });

    test('talks scoring zero are dropped entirely', () {
      final talks = [
        _talk(id: 'talk-001', title: 'Quantization in Practice'),
        _talk(id: 'talk-002', title: 'Completely unrelated topic'),
      ];

      final result = _useCase(query: 'quantization', talks: talks);

      expect(result, hasLength(1));
      expect(result.single.talk.id, 'talk-001');
    });

    test('a query matching nothing returns an empty list, never throws', () {
      final talks = [_talk(id: 'talk-001', title: 'Quantization in Practice')];

      final result = _useCase(query: 'zzz-no-match-zzz', talks: talks);

      expect(result, isEmpty);
    });

    test('an empty talks list returns an empty list', () {
      final result = _useCase(query: 'anything', talks: const []);

      expect(result, isEmpty);
    });

    test('sorts by score descending', () {
      final talks = [
        _talk(id: 'talk-low', title: 'Something else', abstract: 'edge'),
        _talk(id: 'talk-high', title: 'Edge computing', abstract: 'edge'),
      ];

      final result = _useCase(query: 'edge', talks: talks);

      expect(result.map((r) => r.talk.id).toList(), ['talk-high', 'talk-low']);
    });

    test('ties in score are broken by titleMatchCount descending', () {
      // Both talks score 3 total, but talk-a matches one query token
      // ("quantum") in its title (weight x3, titleMatchCount 1) while
      // talk-b matches the same total weight spread across a speaker name
      // (x2) and its abstract (x1), for the two different query tokens,
      // never touching the title (titleMatchCount 0) — talk-a must sort
      // first.
      final talks = [
        _talk(
          id: 'talk-b',
          title: 'Unrelated',
          speakers: const [Speaker(name: 'Edge Runner', title: 'Eng')],
          abstract: 'A quantum overview.',
        ),
        _talk(id: 'talk-a', title: 'Quantum Computing'),
      ];

      final result = _useCase(query: 'quantum edge', talks: talks);

      expect(result.first.talk.id, 'talk-a');
      expect(result.first.score, 3);
      expect(result.first.titleMatchCount, 1);
      expect(result.last.talk.id, 'talk-b');
      expect(result.last.score, 3);
      expect(result.last.titleMatchCount, 0);
    });

    test('ties in score and titleMatchCount are broken by startTime '
        'ascending', () {
      final talks = [
        _talk(
          id: 'talk-later',
          title: 'Edge computing later',
          startTime: DateTime(2026, 11, 10, 14),
        ),
        _talk(
          id: 'talk-earlier',
          title: 'Edge computing earlier',
          startTime: DateTime(2026, 11, 10, 9),
        ),
      ];

      final result = _useCase(query: 'edge', talks: talks);

      expect(result.map((r) => r.talk.id).toList(), [
        'talk-earlier',
        'talk-later',
      ]);
    });

    test('ties in score, titleMatchCount and startTime are broken by id '
        'ascending', () {
      final sameTime = DateTime(2026, 11, 10, 9);
      final talks = [
        _talk(id: 'talk-002', title: 'Edge computing', startTime: sameTime),
        _talk(id: 'talk-001', title: 'Edge computing', startTime: sameTime),
      ];

      final result = _useCase(query: 'edge', talks: talks);

      expect(result.map((r) => r.talk.id).toList(), ['talk-001', 'talk-002']);
    });

    test('only the top 3 matches are returned', () {
      final talks = List.generate(
        5,
        (i) => _talk(
          id: 'talk-$i',
          title: 'Edge computing talk $i',
          startTime: DateTime(2026, 11, 10, 9 + i),
        ),
      );

      final result = _useCase(query: 'edge', talks: talks);

      expect(result, hasLength(3));
      expect(result.map((r) => r.talk.id).toList(), [
        'talk-0',
        'talk-1',
        'talk-2',
      ]);
    });

    test('multiple speakers are all searchable', () {
      final talks = [
        _talk(
          id: 'talk-001',
          title: 'Unrelated',
          speakers: const [
            Speaker(name: 'Priya Natarajan', title: 'Staff Engineer'),
            Speaker(name: 'Diego Fuentes', title: 'Mobile Engineer'),
          ],
        ),
      ];

      final result = _useCase(query: 'Fuentes', talks: talks);

      expect(result.single.score, 2);
    });
  });
}
