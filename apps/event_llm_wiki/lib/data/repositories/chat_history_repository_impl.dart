// See `agenda_repository_impl.dart`'s matching comment: named-parameter
// fields are assigned manually (not via initializing formals) so
// `main.dart` can still pass them by name.
// ignore_for_file: prefer_initializing_formals

import 'package:hive/hive.dart';

import '../../domain/models/chat_message.dart';
import '../../domain/models/citation.dart';
import '../../domain/models/talk.dart';
import '../../domain/repositories/agenda_repository.dart';
import '../../domain/repositories/chat_history_repository.dart';
import '../models/chat_message_dto.dart';

/// [ChatHistoryRepository] backed by a Hive `Box<ChatMessageDto>` (see
/// `doc/adr/0004-persistence-hive-chat-history.md`).
///
/// [agendaRepository] is injected so [getAll] can resolve each persisted
/// message's `citedTalkIds` back into full `Citation`s (talk title
/// included) via `ChatMessageDto.toDomain`'s `resolveCitation` callback,
/// without `ChatMessageDto` itself depending on `AgendaRepository`.
class ChatHistoryRepositoryImpl implements ChatHistoryRepository {
  ChatHistoryRepositoryImpl({
    required Box<ChatMessageDto> box,
    required AgendaRepository agendaRepository,
  }) : _box = box,
       _agendaRepository = agendaRepository;

  final Box<ChatMessageDto> _box;
  final AgendaRepository _agendaRepository;

  @override
  Future<List<ChatMessage>> getAll() async {
    try {
      // Pre-fetch every talk once so `ChatMessageDto.toDomain`'s
      // `resolveCitation` callback (deliberately synchronous — see that
      // method's doc comment) can look citations up from an in-memory map
      // instead of awaiting `AgendaRepository.getTalkById` per citation.
      final talksById = <String, Talk>{
        for (final talk in await _agendaRepository.getAllTalks()) talk.id: talk,
      };
      Citation? resolveCitation(String talkId) {
        final talk = talksById[talkId];
        if (talk == null) return null;
        return Citation(talkId: talk.id, talkTitle: talk.title);
      }

      final messages =
          _box.values
              .map((dto) => dto.toDomain(resolveCitation: resolveCitation))
              .toList()
            // Oldest first (conversation reading order), per the
            // ChatHistoryRepository contract — explicit rather than relying on
            // Hive's insertion-order iteration.
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
  Future<void> add(ChatMessage message) async {
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
}
