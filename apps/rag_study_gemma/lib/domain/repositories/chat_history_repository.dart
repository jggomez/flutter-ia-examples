import '../../core/error/app_exception.dart';
import '../models/chat_message.dart';

/// Thrown when reading, appending, or clearing persisted chat history fails.
class ChatPersistenceException extends AppException {
  const ChatPersistenceException(super.message, {super.cause});
}

/// Contract for persisting and retrieving StudyGemma conversation history.
abstract interface class ChatHistoryRepository {
  Future<List<ChatMessage>> getAll();

  Future<void> append(ChatMessage message);

  Future<void> clear();
}
