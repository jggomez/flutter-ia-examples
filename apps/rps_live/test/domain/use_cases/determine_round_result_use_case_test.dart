import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/use_cases/determine_round_result_use_case.dart';

void main() {
  const useCase = DetermineRoundResultUseCase();

  // Exhaustive 3x3 table, from the player's perspective.
  const expected = <(Move, Move), RoundOutcome>{
    (Move.paper, Move.paper): RoundOutcome.tie,
    (Move.paper, Move.rock): RoundOutcome.win, // paper covers rock
    (Move.paper, Move.scissors): RoundOutcome.lose, // scissors cut paper
    (Move.rock, Move.paper): RoundOutcome.lose, // paper covers rock
    (Move.rock, Move.rock): RoundOutcome.tie,
    (Move.rock, Move.scissors): RoundOutcome.win, // rock crushes scissors
    (Move.scissors, Move.paper): RoundOutcome.win, // scissors cut paper
    (Move.scissors, Move.rock): RoundOutcome.lose, // rock crushes scissors
    (Move.scissors, Move.scissors): RoundOutcome.tie,
  };

  for (final entry in expected.entries) {
    final (playerMove, aiMove) = entry.key;
    test('player $playerMove vs ai $aiMove -> ${entry.value.name}', () {
      final result = useCase(playerMove: playerMove, aiMove: aiMove);
      expect(result, entry.value);
    });
  }

  test('covers every Move x Move combination exhaustively', () {
    expect(expected.length, Move.values.length * Move.values.length);
  });
}
