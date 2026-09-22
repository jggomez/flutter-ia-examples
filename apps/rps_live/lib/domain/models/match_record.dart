import 'move.dart';
import 'round_outcome.dart';

/// A single persisted "Tú vs. IA" round, as read from / written to
/// [HistoryRepository] (see `domain/repositories/history_repository.dart`).
///
/// This is the domain shape used by the UI and game logic. The data layer
/// maps it to/from a Hive-persisted DTO in `data/models/match_record_dto.dart`
/// — the domain layer must never import `package:hive`.
class MatchRecord {
  const MatchRecord({
    required this.id,
    required this.playedAt,
    required this.playerMove,
    required this.aiMove,
    required this.outcome,
  });

  /// Stable unique id (e.g. uuid) so history entries can be referenced
  /// without relying on list position.
  final String id;

  final DateTime playedAt;
  final Move playerMove;
  final Move aiMove;
  final RoundOutcome outcome;
}
