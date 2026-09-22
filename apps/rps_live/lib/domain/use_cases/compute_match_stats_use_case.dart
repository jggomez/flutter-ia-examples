import '../models/match_record.dart';
import '../models/match_stats.dart';
import '../models/round_outcome.dart';

/// Derives aggregate win/lose/tie [MatchStats] from a list of [MatchRecord]s.
///
/// Kept as its own pure use case (rather than computed ad hoc in
/// `HistoryViewModel`/`HistoryScreen`) so the aggregation rule is unit
/// tested independently of Riverpod/widgets.
class ComputeMatchStatsUseCase {
  const ComputeMatchStatsUseCase();

  MatchStats call(List<MatchRecord> records) {
    var wins = 0;
    var losses = 0;
    var ties = 0;
    for (final record in records) {
      switch (record.outcome) {
        case RoundOutcome.win:
          wins++;
        case RoundOutcome.lose:
          losses++;
        case RoundOutcome.tie:
          ties++;
      }
    }
    return MatchStats(wins: wins, losses: losses, ties: ties);
  }
}
