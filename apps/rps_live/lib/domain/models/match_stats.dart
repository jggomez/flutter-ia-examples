/// Aggregate win/lose/tie counts derived from a list of [MatchRecord]s (see
/// `domain/use_cases/compute_match_stats_use_case.dart`).
///
/// Kept separate from [MatchRecord] itself since it is a derived, in-memory
/// value — never persisted on its own (see `doc/adr/0002-persistence-hive.md`:
/// aggregate stats are computed, not stored redundantly).
class MatchStats {
  const MatchStats({
    required this.wins,
    required this.losses,
    required this.ties,
  });

  const MatchStats.zero() : this(wins: 0, losses: 0, ties: 0);

  final int wins;
  final int losses;
  final int ties;

  int get total => wins + losses + ties;

  /// Win rate in `[0, 1]` over all played rounds, or `0` if none were
  /// played (avoids a division-by-zero `NaN` in the UI).
  double get winRate => total == 0 ? 0 : wins / total;

  @override
  bool operator ==(Object other) =>
      other is MatchStats &&
      other.wins == wins &&
      other.losses == losses &&
      other.ties == ties;

  @override
  int get hashCode => Object.hash(wins, losses, ties);

  @override
  String toString() => 'MatchStats(wins: $wins, losses: $losses, ties: $ties)';
}
