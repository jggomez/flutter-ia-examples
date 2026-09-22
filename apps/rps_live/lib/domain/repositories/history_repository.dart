import '../../core/error/app_exception.dart';
import '../models/match_record.dart';

/// Abstraction over persisted match history (see
/// `doc/adr/0002-persistence-hive.md` for why Hive backs the real
/// implementation).
///
/// `data/repositories/history_repository_impl.dart` implements this against
/// a Hive box; tests use an in-memory `FakeHistoryRepository` (a plain
/// `List<MatchRecord>` in memory) so game-logic and view-model tests never
/// touch Hive or the filesystem.
abstract class HistoryRepository {
  /// All persisted rounds, most recent first. Aggregate stats (win/lose/tie
  /// counts) are derived from this list in the domain/use-case layer, not
  /// stored redundantly.
  Future<List<MatchRecord>> getAll();

  /// Appends a completed round to history.
  ///
  /// Throws [HistoryPersistenceException] if the write fails (e.g. box not
  /// open, disk error) — callers must not assume this always succeeds.
  Future<void> add(MatchRecord record);

  /// Clears all history (e.g. a "reset stats" action).
  Future<void> clear();
}

/// Thrown when reading from or writing to the underlying store fails.
class HistoryPersistenceException extends AppException {
  const HistoryPersistenceException(super.message, {super.cause});
}
