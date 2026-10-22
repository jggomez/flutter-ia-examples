/// Hive box/type-id registry.
///
/// Centralized so `typeId`s are never accidentally reused across DTOs
/// (Hive silently corrupts data on a `typeId` collision) and box names have
/// one source of truth for `ChatHistoryRepositoryImpl` and app bootstrap
/// (`Hive.openBox`). Mirrors `apps/rps_live/lib/data/local/hive_boxes.dart`'s
/// convention.
abstract final class HiveBoxes {
  static const String chatHistory = 'chat_history';
}

/// Hive `typeId` registry — bump the comment trail below every time a new
/// `@HiveType` is added; never reuse a retired id.
///
/// - 0: `ChatMessageDto` (`data/models/chat_message_dto.dart`)
///
/// Only one DTO exists in this app (chat history — see
/// `doc/adr/0004-persistence-hive-chat-history.md`; model-download progress
/// is deliberately NOT persisted, so there is no DTO for it).
abstract final class HiveTypeIds {
  static const int chatMessageDto = 0;
}
