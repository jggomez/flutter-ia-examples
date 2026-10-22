import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/chat_role.dart';
import '../../../../domain/models/citation.dart';
import '../../../../domain/use_cases/build_chat_prompt_use_case.dart';
import '../../../../domain/use_cases/retrieve_relevant_talks_use_case.dart';
import '../../../providers/repository_providers.dart';

/// Drives the single-thread chat conversation: loads persisted history,
/// initializes the on-device engine, and — per [sendMessage] — retrieves
/// relevant talks, builds the grounded prompt, streams the model's answer,
/// and persists the completed turn.
///
/// `AsyncNotifier<List<ChatMessage>>` — [build] resolves once history is
/// loaded and the engine is initialized; after that, [sendMessage] mutates
/// `state` directly (appending the user message, then updating the
/// in-progress assistant message's text as stream deltas arrive, exactly
/// like `apps/rps_live`'s `PracticeViewModel` bridges its push-based stream
/// into `AsyncValue` — see that class's doc comment for the pattern this
/// mirrors).
///
/// `flutter-implementer`: `build()` should call
/// `ref.watch(chatEngineRepositoryProvider).initialize()` before returning,
/// since `ChatTabRoot` only mounts `ChatScreen` (and thus this provider)
/// once `ModelDownloadViewModel` reports `ModelDownloadPhase.ready` — by
/// that point a validated model file is guaranteed to exist, so
/// `initialize()` here should not itself need a "is the model ready" check.
class ChatViewModel extends AsyncNotifier<List<ChatMessage>> {
  static const _retrieveRelevantTalksUseCase = RetrieveRelevantTalksUseCase();
  static const _buildChatPromptUseCase = BuildChatPromptUseCase();

  @override
  Future<List<ChatMessage>> build() async {
    // `ChatTabRoot` only mounts `ChatScreen` (and thus this provider) once
    // `ModelDownloadViewModel` reports `ModelDownloadPhase.ready`, so a
    // validated model file is guaranteed to exist by the time this runs.
    await ref.watch(chatEngineRepositoryProvider).initialize();
    return ref.watch(chatHistoryRepositoryProvider).getAll();
  }

  /// Sends [questionText] as a new user turn: appends it to `state`
  /// immediately, retrieves relevant talks via
  /// [_retrieveRelevantTalksUseCase] against `agendaRepositoryProvider`'s
  /// talks, builds the grounded prompt via [_buildChatPromptUseCase],
  /// streams the answer from `chatEngineRepositoryProvider`, and persists
  /// both the user and assistant messages via `chatHistoryRepositoryProvider`
  /// once the assistant's stream completes.
  ///
  /// ## Delta-stream accumulation
  ///
  /// `ChatEngineRepository.sendMessage`'s `Stream<String>` emits DELTAS
  /// (new tokens only per event, not a cumulative snapshot — see that
  /// method's doc comment and `LitertLmService`'s). This view model is the
  /// layer that accumulates those deltas into the growing message text: a
  /// local `StringBuffer` is appended to on every emission, and the
  /// in-progress assistant [ChatMessage] in `state` is replaced with a new
  /// copy carrying `buffer.toString()` each time — so `ChatScreen` always
  /// renders the full accumulated text so far, never a raw delta, and never
  /// double-concatenates.
  Future<void> sendMessage(String questionText) async {
    final currentMessages = state.value ?? const <ChatMessage>[];
    final now = DateTime.now();
    final userMessage = ChatMessage(
      id: _generateId('user'),
      role: ChatRole.user,
      text: questionText,
      createdAt: now,
    );
    // Appended to `state` immediately (synchronously, before any `await`),
    // so `ChatScreen` shows the user's question right away rather than
    // waiting on retrieval/generation to even start.
    state = AsyncData([...currentMessages, userMessage]);

    final talks = await ref.read(agendaRepositoryProvider).getAllTalks();
    final retrievedTalks = _retrieveRelevantTalksUseCase(
      query: questionText,
      talks: talks,
    );
    final citations = [
      for (final retrieved in retrievedTalks)
        Citation(talkId: retrieved.talk.id, talkTitle: retrieved.talk.title),
    ];
    final prompt = _buildChatPromptUseCase(
      userQuestion: questionText,
      retrievedTalks: retrievedTalks,
    );

    final assistantId = _generateId('assistant');
    ChatMessage assistantMessage = ChatMessage(
      id: assistantId,
      role: ChatRole.assistant,
      text: '',
      createdAt: DateTime.now(),
      citations: citations,
    );
    state = AsyncData([...currentMessages, userMessage, assistantMessage]);

    void updateAssistantMessage(String text) {
      assistantMessage = ChatMessage(
        id: assistantId,
        role: ChatRole.assistant,
        text: text,
        createdAt: assistantMessage.createdAt,
        citations: citations,
      );
      state = AsyncData([...currentMessages, userMessage, assistantMessage]);
    }

    final buffer = StringBuffer();
    final chatEngineRepository = ref.read(chatEngineRepositoryProvider);
    try {
      await for (final delta in chatEngineRepository.sendMessage(prompt)) {
        buffer.write(delta);
        updateAssistantMessage(buffer.toString());
      }
    } catch (_) {
      // A mid-stream inference failure still leaves whatever text was
      // generated so far as a usable (if incomplete) answer, rather than
      // losing the user's turn or leaving the view model stuck — see this
      // method's doc comment.
      updateAssistantMessage(buffer.toString());
    }

    final chatHistoryRepository = ref.read(chatHistoryRepositoryProvider);
    await chatHistoryRepository.add(userMessage);
    await chatHistoryRepository.add(assistantMessage);
  }

  String _generateId(String suffix) =>
      '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

/// Deliberately NOT `.autoDispose` — the single documented exception to
/// `apps/rps_live`'s `.autoDispose`-by-default convention. See
/// `doc/adr/0003-state-management-riverpod.md` for the full rationale: this
/// app has exactly one consumer of the ~529 MB on-device engine (this
/// view model), so the engine should load once and stay loaded for the
/// app session rather than reload every time the user switches away from
/// and back to the Chat tab. `ChatEngineRepositoryImpl`'s idempotent-init
/// guard (not full reference counting, unlike `apps/rps_live`'s
/// `ClassifierRepositoryImpl`) depends on this provider never being torn
/// down mid-session.
final chatViewModelProvider =
    AsyncNotifierProvider<ChatViewModel, List<ChatMessage>>(
      ChatViewModel.new,
      // See `agendaListViewModelProvider`'s matching comment: a failed
      // `initialize()`/history load is not transient, so Riverpod's
      // default retry-on-error is disabled here too.
      retry: (retryCount, error) => null,
    );
