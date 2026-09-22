/// Hive box/type-id registry.
///
/// Centralized so `typeId`s are never accidentally reused across DTOs
/// (Hive silently corrupts data on a `typeId` collision) and box names have
/// one source of truth for `HistoryRepositoryImpl` and app bootstrap
/// (`Hive.openBox`).
abstract final class HiveBoxes {
  static const String matchHistory = 'match_history';
}

/// Hive `typeId` registry — bump the comment trail below every time a new
/// `@HiveType` is added; never reuse a retired id.
///
/// - 0: `MatchRecordDto` (`data/models/match_record_dto.dart`)
abstract final class HiveTypeIds {
  static const int matchRecordDto = 0;
}
