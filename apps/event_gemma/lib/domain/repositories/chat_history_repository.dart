import '../../core/error/app_exception.dart';
import '../models/chat_message.dart';

/// Abstraction over persisted single-thread chat history (see
/// `doc/adr/0004-persistence-hive-chat-history.md` for why Hive backs the
/// real implementation, and why only `citedTalkIds` — not full `Talk`
/// objects — are persisted per message).
///
/// `data/repositories/chat_history_repository_impl.dart` implements this
/// against a Hive box; tests use an in-memory `FakeChatHistoryRepository`
/// so use-case/view-model tests never touch Hive or the filesystem.
abstract class ChatHistoryRepository {
  /// All persisted messages, oldest first (conversation reading order).
  ///
  /// Throws [ChatPersistenceException] if the read fails.
  Future<List<ChatMessage>> getAll();

  /// Appends a completed message (user question or full assistant answer —
  /// never a partial/streaming-in-progress one) to history.
  ///
  /// Throws [ChatPersistenceException] if the write fails.
  Future<void> add(ChatMessage message);
}

/// Thrown when reading from or writing to the underlying chat history store
/// fails.
class ChatPersistenceException extends AppException {
  const ChatPersistenceException(super.message, {super.cause});
}
