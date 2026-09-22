import 'move.dart';

/// A single classifier inference, decoded from the raw `[1, 3]` softmax
/// output tensor into a domain-friendly shape.
///
/// This is the type exposed by [ClassifierRepository.classificationStream]
/// (see `domain/repositories/classifier_repository.dart`) — both the "Tú vs.
/// IA" round logic and the live confidence meter consume it, so it must stay
/// free of any camera/tflite/plugin types to remain trivially fake-able in
/// tests.
class ClassificationResult {
  const ClassificationResult({
    required this.paperConfidence,
    required this.rockConfidence,
    required this.scissorsConfidence,
  });

  /// Softmax confidence for [Move.paper], in `[0, 1]`.
  final double paperConfidence;

  /// Softmax confidence for [Move.rock], in `[0, 1]`.
  final double rockConfidence;

  /// Softmax confidence for [Move.scissors], in `[0, 1]`.
  final double scissorsConfidence;

  /// Confidence for a given [move], keyed the same way for all three moves
  /// so the live confidence meter can iterate `Move.values` generically.
  double confidenceFor(Move move) {
    switch (move) {
      case Move.paper:
        return paperConfidence;
      case Move.rock:
        return rockConfidence;
      case Move.scissors:
        return scissorsConfidence;
    }
  }

  /// The move with the highest confidence.
  ///
  /// Tie-break rule: iterates [Move.values] in its declared `paper, rock,
  /// scissors` order and keeps the first-seen maximum (a strict `>`
  /// comparison), so an exact tie always resolves to whichever tied move
  /// comes first in that order. No minimum-confidence threshold is applied
  /// here — callers that need to treat a low-confidence read as "no move
  /// detected" should compare [confidenceFor] against their own threshold.
  Move get topMove {
    var best = Move.values.first;
    var bestConfidence = confidenceFor(best);
    for (final move in Move.values.skip(1)) {
      final confidence = confidenceFor(move);
      if (confidence > bestConfidence) {
        best = move;
        bestConfidence = confidence;
      }
    }
    return best;
  }
}
