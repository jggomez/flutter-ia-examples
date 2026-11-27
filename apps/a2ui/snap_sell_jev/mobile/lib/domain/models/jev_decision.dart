import 'package:flutter/foundation.dart';

/// One decision Jev made in the last agent turn, as sent in the
/// `application/vnd.snap-sell.jev-trace+json` DataPart.
@immutable
class JevDecision {
  const JevDecision({
    required this.stage,
    required this.question,
    required this.answer,
    required this.probability,
    required this.outcome,
  });

  /// Parses the `jevTrace` list of a trace DataPart; skips malformed entries.
  static List<JevDecision> listFromTrace(Object? trace) {
    if (trace is! List) return const <JevDecision>[];
    return <JevDecision>[
      for (final Object? entry in trace)
        if (entry is Map && entry['question'] is String)
          JevDecision(
            stage: '${entry['stage'] ?? ''}',
            question: entry['question'] as String,
            answer: '${entry['answer'] ?? ''}',
            probability: (entry['probability'] as num?)?.toDouble() ?? 0,
            outcome: '${entry['outcome'] ?? ''}',
          ),
    ];
  }

  /// `photo`, `form`, `details`, `damage_photo`…
  final String stage;

  /// Question name, e.g. `category` or `field_warrantyActive`.
  final String question;
  final String answer;

  /// Jev's calibrated probability for [answer] (0..1).
  final double probability;

  /// What the code did with it, e.g. `field shown`.
  final String outcome;

  /// `field_warrantyActive` → `warrantyActive` for form-field questions.
  String get label =>
      question.startsWith('field_') ? question.substring(6) : question;

  /// True when this decision added something to the screen.
  bool get changedUi =>
      outcome == 'field shown' ||
      outcome.contains('pre-checked') ||
      outcome.contains('hint shown') ||
      outcome.contains('battery fields');
}
