import 'package:hive/hive.dart';

import '../../domain/models/chat_message.dart';
import '../../domain/repositories/chat_history_repository.dart';
import '../models/chat_message_dto.dart';

/// Implementation of [ChatHistoryRepository] backed by a Hive
/// `Box<ChatMessageDto>`.
class ChatHistoryRepositoryImpl implements ChatHistoryRepository {
  ChatHistoryRepositoryImpl({
    Box<ChatMessageDto>? box,
    Box<ChatMessageDto>? chatHistoryBox,
  }) : _box = _requireBox(box ?? chatHistoryBox);

  final Box<ChatMessageDto> _box;

  static Box<ChatMessageDto> _requireBox(Box<ChatMessageDto>? candidate) {
    if (candidate == null) {
      throw ArgumentError.notNull('box');
    }
    return candidate;
  }

  @override
  Future<List<ChatMessage>> getAll() async {
    try {
      final messages = _box.values.map((dto) => dto.toDomain()).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ChatPersistenceException(
          'Failed to read chat history from Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> append(ChatMessage message) async {
    try {
      await _box.put(message.id, ChatMessageDto.fromDomain(message));
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ChatPersistenceException(
          'Failed to persist chat message ${message.id} to Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _box.clear();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ChatPersistenceException(
          'Failed to clear chat history in Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}
