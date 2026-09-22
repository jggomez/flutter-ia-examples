import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/models/move.dart';

void main() {
  group('topMove', () {
    test('returns the move with strictly the highest confidence', () {
      const paperWins = ClassificationResult(
        paperConfidence: 0.7,
        rockConfidence: 0.2,
        scissorsConfidence: 0.1,
      );
      const rockWins = ClassificationResult(
        paperConfidence: 0.1,
        rockConfidence: 0.8,
        scissorsConfidence: 0.1,
      );
      const scissorsWins = ClassificationResult(
        paperConfidence: 0.2,
        rockConfidence: 0.2,
        scissorsConfidence: 0.6,
      );

      expect(paperWins.topMove, Move.paper);
      expect(rockWins.topMove, Move.rock);
      expect(scissorsWins.topMove, Move.scissors);
    });

    test('breaks an exact tie in Move.values declaration order (paper, '
        'rock, scissors) — the first-encountered maximum wins', () {
      const allTied = ClassificationResult(
        paperConfidence: 0.5,
        rockConfidence: 0.5,
        scissorsConfidence: 0.5,
      );
      const rockAndScissorsTied = ClassificationResult(
        paperConfidence: 0.1,
        rockConfidence: 0.5,
        scissorsConfidence: 0.5,
      );

      expect(allTied.topMove, Move.paper);
      expect(rockAndScissorsTied.topMove, Move.rock);
    });

    test('confidenceFor returns the matching field for every move', () {
      const result = ClassificationResult(
        paperConfidence: 0.1,
        rockConfidence: 0.2,
        scissorsConfidence: 0.3,
      );

      expect(result.confidenceFor(Move.paper), 0.1);
      expect(result.confidenceFor(Move.rock), 0.2);
      expect(result.confidenceFor(Move.scissors), 0.3);
    });
  });
}
