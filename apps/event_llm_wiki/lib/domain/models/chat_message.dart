import 'chat_role.dart';
import 'citation.dart';

/// A single turn in the single-thread chat conversation with the offline
/// RAG assistant.
///
/// This is the in-memory/domain shape; `data/models/chat_message_dto.dart`
/// is its Hive-persisted counterpart (see
/// `doc/adr/0004-persistence-hive-chat-history.md`).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.citations = const [],
  });

  final String id;

  final ChatRole role;

  /// Full message text. For a streaming assistant reply, this is expected to
  /// be built up incrementally by the view model as
  /// `ChatEngineRepository.sendMessage(prompt)`'s stream emits deltas, then
  /// persisted once as a complete [ChatMessage] when the stream finishes.
  final String text;

  final DateTime createdAt;

  /// Talks this answer is grounded in. Always empty for [ChatRole.user]
  /// messages. May be empty for a [ChatRole.assistant] message too — that is
  /// the expected, honest shape of a "no matching talk" answer (see
  /// `BuildChatPromptUseCase`), not an error state.
  final List<Citation> citations;
}
