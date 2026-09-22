import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/match_stats.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/use_cases/compute_match_stats_use_case.dart';

MatchRecord _record(RoundOutcome outcome) => MatchRecord(
  id: 'id-${outcome.name}-${identityHashCode(outcome)}',
  playedAt: DateTime(2026),
  playerMove: Move.rock,
  aiMove: Move.scissors,
  outcome: outcome,
);

void main() {
  const useCase = ComputeMatchStatsUseCase();

  test('returns all-zero stats for an empty history', () {
    expect(useCase(const []), const MatchStats.zero());
  });

  test('counts wins, losses and ties independently', () {
    final records = [
      _record(RoundOutcome.win),
      _record(RoundOutcome.win),
      _record(RoundOutcome.lose),
      _record(RoundOutcome.tie),
      _record(RoundOutcome.tie),
      _record(RoundOutcome.tie),
    ];

    final stats = useCase(records);

    expect(stats.wins, 2);
    expect(stats.losses, 1);
    expect(stats.ties, 3);
    expect(stats.total, 6);
  });

  test('winRate divides wins by total, and is 0 (not NaN) when empty', () {
    expect(const MatchStats.zero().winRate, 0);
    expect(
      useCase([_record(RoundOutcome.win), _record(RoundOutcome.lose)]).winRate,
      closeTo(0.5, 1e-9),
    );
  });
}
