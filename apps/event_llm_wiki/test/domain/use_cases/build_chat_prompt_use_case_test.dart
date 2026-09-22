import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/retrieved_talk.dart';
import 'package:event_llm_wiki/domain/models/speaker.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/domain/use_cases/build_chat_prompt_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

const _useCase = BuildChatPromptUseCase();

RetrievedTalk _retrieved({
  required String id,
  required String title,
  String abstract = 'An abstract.',
  List<Speaker> speakers = const [Speaker(name: 'Ada Solano', title: 'Eng')],
}) => RetrievedTalk(
  talk: Talk(
    id: id,
    title: title,
    abstract: abstract,
    speakers: speakers,
    day: ConferenceDay.dayOne,
    track: ConferenceTrack.engineering,
    startTime: DateTime(2026, 11, 10, 9),
    durationMinutes: 45,
  ),
  score: 3,
  titleMatchCount: 1,
);

void main() {
  group('BuildChatPromptUseCase', () {
    test('includes the user question verbatim', () {
      final prompt = _useCase(
        userQuestion: 'What is talk-001 about?',
        retrievedTalks: const [],
      );

      expect(prompt, contains('What is talk-001 about?'));
    });

    test('an empty retrievedTalks list produces an explicit "no matching '
        'talk" instruction', () {
      final prompt = _useCase(
        userQuestion: 'Is there a talk about knitting?',
        retrievedTalks: const [],
      );

      expect(prompt.toLowerCase(), contains('no matching talk'));
      expect(prompt.toLowerCase(), contains('agenda'));
    });

    test('a non-empty retrievedTalks list grounds the prompt in each '
        "talk's title/speakers/abstract/day/track/time", () {
      final talk = _retrieved(
        id: 'talk-001',
        title: 'On-Device LLMs',
        abstract: 'A tour of the edge inference landscape.',
        speakers: const [
          Speaker(name: 'Ada Solano', title: 'Principal Engineer'),
        ],
      );

      final prompt = _useCase(
        userQuestion: 'What is On-Device LLMs about?',
        retrievedTalks: [talk],
      );

      expect(prompt, contains('On-Device LLMs'));
      expect(prompt, contains('Ada Solano'));
      expect(prompt, contains('A tour of the edge inference landscape.'));
      expect(prompt, contains('Day 1'));
      expect(prompt, contains('Engineering'));
    });

    test('does not contain the "no matching talk" instruction when '
        'retrievedTalks is non-empty', () {
      final prompt = _useCase(
        userQuestion: 'What is On-Device LLMs about?',
        retrievedTalks: [_retrieved(id: 'talk-001', title: 'On-Device LLMs')],
      );

      expect(prompt.toLowerCase(), isNot(contains('no matching talk')));
    });

    test('instructs the model to answer only from the given context, not '
        'to invent information', () {
      final prompt = _useCase(
        userQuestion: 'What is On-Device LLMs about?',
        retrievedTalks: [_retrieved(id: 'talk-001', title: 'On-Device LLMs')],
      );

      // The exact wording is an implementation choice; the important,
      // testable invariant is that grounding/anti-hallucination language is
      // present somewhere in the prompt.
      expect(
        prompt.toLowerCase(),
        anyOf(contains('only'), contains('do not answer beyond')),
      );
    });

    test('renders multiple retrieved talks, each distinguishable in the '
        'prompt text', () {
      final prompt = _useCase(
        userQuestion: 'Tell me about the engineering track.',
        retrievedTalks: [
          _retrieved(id: 'talk-001', title: 'On-Device LLMs'),
          _retrieved(id: 'talk-002', title: 'Quantization in Practice'),
        ],
      );

      expect(prompt, contains('On-Device LLMs'));
      expect(prompt, contains('Quantization in Practice'));
    });

    test('the composed prompt never embeds a special citation-parsing '
        'syntax (citations are computed separately from RetrievedTalk, '
        'never parsed back out of model text)', () {
      final prompt = _useCase(
        userQuestion: 'What is On-Device LLMs about?',
        retrievedTalks: [_retrieved(id: 'talk-001', title: 'On-Device LLMs')],
      );

      expect(prompt, isNot(contains('[[cite:')));
      expect(prompt, isNot(contains('{{citation}}')));
    });
  });
}
