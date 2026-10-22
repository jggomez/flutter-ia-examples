import 'talk.dart';

/// Output of `RetrieveRelevantTalksUseCase`: a [talk] plus its ranking
/// signals, in the weighted-lexical-scoring scheme described in
/// `doc/adr/0002-rag-lexical-retrieval.md`.
///
/// Sort order (highest relevance first) is: [score] desc, then
/// [titleMatchCount] desc, then `talk.startTime` asc, then `talk.id` asc —
/// the last two fields exist purely to make the ranking fully deterministic
/// (no ties reach the caller in an unspecified order), which matters both
/// for citation-chip stability across repeated identical queries and for
/// exhaustive fixture-based unit tests.
class RetrievedTalk {
  const RetrievedTalk({
    required this.talk,
    required this.score,
    required this.titleMatchCount,
  });

  final Talk talk;

  /// Weighted sum of query-token matches across title (x3), speaker names
  /// (x2), track/day (x1), and abstract (x1).
  final int score;

  /// Number of query tokens that matched [Talk.title] specifically — used
  /// only as the first tie-break below [score].
  final int titleMatchCount;
}
