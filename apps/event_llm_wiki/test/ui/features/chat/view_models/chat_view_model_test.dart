import 'package:event_llm_wiki/domain/models/chat_role.dart';
import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/ui/features/chat/view_models/chat_view_model.dart';
import 'package:event_llm_wiki/ui/providers/repository_providers.dart';
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

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

class _Harness {
  _Harness({List<Talk>? talks}) {
    agenda = FakeAgendaRepository(seed: talks ?? [_talk('talk-001')]);
    engine = FakeChatEngineRepository();
    history = FakeChatHistoryRepository();
    container = ProviderContainer(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(agenda),
        chatEngineRepositoryProvider.overrideWithValue(engine),
        chatHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
  }

  late FakeAgendaRepository agenda;
  late FakeChatEngineRepository engine;
  late FakeChatHistoryRepository history;
  late ProviderContainer container;

  Future<void> dispose() async => container.dispose();
}

void main() {
  group('ChatViewModel', () {
    test('build() initializes the chat engine exactly once and loads '
        'persisted history', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      final messages = await harness.container.read(
        chatViewModelProvider.future,
      );

      expect(messages, isEmpty);
      expect(harness.engine.initializeCallCount, 1);
    });

    test('sendMessage appends a user message immediately', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('What is On-Device LLMs about?');
      await _flushMicrotasks();

      final state = harness.container.read(chatViewModelProvider).value!;
      expect(state.first.role, ChatRole.user);
      expect(state.first.text, 'What is On-Device LLMs about?');

      harness.engine.emit('It');
      await harness.engine.completeStream();
      await future;
    });

    test('streamed deltas accumulate (append, not overwrite) into a '
        'growing assistant message', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('What is On-Device LLMs about?');
      await _flushMicrotasks();

      harness.engine.emit('It is');
      await _flushMicrotasks();
      expect(
        harness.container.read(chatViewModelProvider).value!.last.text,
        'It is',
      );

      harness.engine.emit(' a talk');
      await _flushMicrotasks();
      expect(
        harness.container.read(chatViewModelProvider).value!.last.text,
        'It is a talk',
      );

      harness.engine.emit(' about edge inference.');
      await harness.engine.completeStream();
      await future;

      final finalState = harness.container.read(chatViewModelProvider).value!;
      expect(finalState.last.text, 'It is a talk about edge inference.');
      expect(finalState.last.role, ChatRole.assistant);
    });

    test('attaches citations from RetrieveRelevantTalksUseCase to the '
        'assistant message, computed before generation', () async {
      final harness = _Harness(
        talks: [_talk('talk-001', title: 'On-Device LLMs')],
      );
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('Tell me about On-Device LLMs');
      await _flushMicrotasks();
      harness.engine.emit('It is great.');
      await harness.engine.completeStream();
      await future;

      final assistantMessage = harness.container
          .read(chatViewModelProvider)
          .value!
          .last;
      expect(assistantMessage.citations, hasLength(1));
      expect(assistantMessage.citations.single.talkId, 'talk-001');
      expect(assistantMessage.citations.single.talkTitle, 'On-Device LLMs');
    });

    test('a question with no agenda match gets zero citations', () async {
      final harness = _Harness(talks: [_talk('talk-001')]);
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('zzz-completely-unrelated-zzz');
      await _flushMicrotasks();
      harness.engine.emit("I couldn't find a matching talk.");
      await harness.engine.completeStream();
      await future;

      final assistantMessage = harness.container
          .read(chatViewModelProvider)
          .value!
          .last;
      expect(assistantMessage.citations, isEmpty);
    });

    test('persists both the user and assistant messages once the stream '
        'completes', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('What is On-Device LLMs about?');
      await _flushMicrotasks();
      harness.engine.emit('It is a talk.');
      await harness.engine.completeStream();
      await future;

      final persisted = await harness.history.getAll();
      expect(persisted, hasLength(2));
      expect(persisted[0].role, ChatRole.user);
      expect(persisted[1].role, ChatRole.assistant);
      expect(persisted[1].text, 'It is a talk.');
    });

    test('the prompt sent to the engine is grounded via '
        'BuildChatPromptUseCase, not the raw question', () async {
      final harness = _Harness(
        talks: [_talk('talk-001', title: 'On-Device LLMs')],
      );
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('Tell me about On-Device LLMs');
      await _flushMicrotasks();
      harness.engine.emit('answer');
      await harness.engine.completeStream();
      await future;

      expect(harness.engine.lastPrompt, contains('On-Device LLMs'));
      expect(
        harness.engine.lastPrompt,
        contains('Tell me about On-Device LLMs'),
      );
    });

    test('a mid-stream inference failure finalizes the assistant message '
        'instead of leaving the view model stuck', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.container.read(chatViewModelProvider.future);

      final future = harness.container
          .read(chatViewModelProvider.notifier)
          .sendMessage('What is On-Device LLMs about?');
      await _flushMicrotasks();
      harness.engine.emit('Partial');
      harness.engine.emitError(Exception('mid-stream failure'));
      await future;

      final state = harness.container.read(chatViewModelProvider).value!;
      expect(state.last.role, ChatRole.assistant);
      expect(state.last.text, contains('Partial'));
    });
  });
}
