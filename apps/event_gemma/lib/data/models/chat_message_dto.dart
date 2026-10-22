import 'package:hive/hive.dart';

import '../../domain/models/chat_message.dart';
import '../../domain/models/chat_role.dart';
import '../../domain/models/citation.dart';
import '../local/hive_boxes.dart';

part 'chat_message_dto.g.dart';

/// Hive-persisted shape for a [ChatMessage].
///
/// Deliberately stores only [citedTalkIds] (talk ids), not full `Talk`
/// objects or even denormalized titles — see
/// `doc/adr/0004-persistence-hive-chat-history.md` for why: the agenda is
/// already bundled in `assets/agenda.json`, so persisting talk content
/// again per chat message would duplicate data that can go stale
/// independently. `ChatHistoryRepositoryImpl` re-joins [citedTalkIds]
/// against `AgendaRepository` (via [toDomain]'s `resolveCitation` callback)
/// to rebuild the full [Citation] list (including [Citation.talkTitle])
/// when history is loaded back.
@HiveType(typeId: HiveTypeIds.chatMessageDto)
class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.roleIndex,
    required this.text,
    required this.createdAtMillisSinceEpoch,
    required this.citedTalkIds,
  });

  @HiveField(0)
  final String id;

  /// `ChatRole.values[roleIndex]`.
  @HiveField(1)
  final int roleIndex;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final int createdAtMillisSinceEpoch;

  /// Talk ids this message cites. Empty for user messages and for "no
  /// matching talk" assistant answers.
  @HiveField(4)
  final List<String> citedTalkIds;

  factory ChatMessageDto.fromDomain(ChatMessage message) => ChatMessageDto(
    id: message.id,
    roleIndex: message.role.index,
    text: message.text,
    createdAtMillisSinceEpoch: message.createdAt.millisecondsSinceEpoch,
    citedTalkIds: [for (final citation in message.citations) citation.talkId],
  );

  /// Rebuilds the domain [ChatMessage], resolving [citedTalkIds] into full
  /// [Citation]s via [resolveCitation] (expected to be backed by
  /// `AgendaRepository.getTalkById`, or an equivalent in-memory lookup —
  /// `ChatMessageDto` itself must never import `AgendaRepository` or do
  /// async work).
  ///
  /// A talk id [resolveCitation] cannot resolve (e.g. `assets/agenda.json`
  /// changed since this message was persisted) is silently dropped from the
  /// rebuilt citation list rather than surfaced as an error — a missing
  /// citation chip is a better failure mode than crashing history load.
  ChatMessage toDomain({
    required Citation? Function(String talkId) resolveCitation,
  }) => ChatMessage(
    id: id,
    role: ChatRole.values[roleIndex],
    text: text,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillisSinceEpoch),
    citations: [for (final talkId in citedTalkIds) ?resolveCitation(talkId)],
  );
}
