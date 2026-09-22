import '../models/move.dart';
import '../models/round_outcome.dart';

/// Pure Rock/Paper/Scissors win/lose/tie rule, decoupled from the classifier
/// and from any UI/timing concerns so it is trivially unit-testable
/// (3 moves x 3 moves = 9 cases, fully enumerable).
class DetermineRoundResultUseCase {
  const DetermineRoundResultUseCase();

  /// Outcome for [playerMove] against [aiMove], from the player's
  /// perspective.
  RoundOutcome call({required Move playerMove, required Move aiMove}) {
    if (playerMove == aiMove) {
      return RoundOutcome.tie;
    }
    if (_beats(playerMove) == aiMove) {
      return RoundOutcome.win;
    }
    return RoundOutcome.lose;
  }

  /// The move that [move] beats (standard rock/paper/scissors rules: paper
  /// covers rock, rock crushes scissors, scissors cut paper).
  Move _beats(Move move) {
    switch (move) {
      case Move.paper:
        return Move.rock;
      case Move.rock:
        return Move.scissors;
      case Move.scissors:
        return Move.paper;
    }
  }
}
