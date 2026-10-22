/// A single agenda citation attached to an assistant [ChatMessage] — one of
/// the talks the answer is grounded in.
///
/// Citations are computed BEFORE generation, from
/// `RetrieveRelevantTalksUseCase`'s output (see
/// `doc/adr/0002-rag-lexical-retrieval.md`) — never parsed out of the
/// model's own free-text response. [talkTitle] is denormalized alongside
/// [talkId] so a citation chip can render without an extra
/// `AgendaRepository` lookup; `ChatMessageDto` (the persisted shape) stores
/// only the id (see `doc/adr/0004-persistence-hive-chat-history.md`) and
/// `ChatHistoryRepositoryImpl` re-joins against the in-memory agenda cache
/// to rebuild the full [Citation] list when a message is loaded back from
/// Hive.
class Citation {
  const Citation({required this.talkId, required this.talkTitle});

  final String talkId;
  final String talkTitle;
}
