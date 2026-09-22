import '../models/conference_day.dart';
import '../models/conference_track.dart';
import '../models/retrieved_talk.dart';
import '../models/talk.dart';

/// Plain-Dart lexical/keyword field-weighted retrieval over the bundled
/// agenda — the entire "R" in this app's offline RAG pipeline (see
/// `doc/adr/0002-rag-lexical-retrieval.md`; deliberately no embeddings, no
/// vector index, no sqlite/FTS5).
///
/// `flutter-implementer` fills in [call]'s body per the ADR's algorithm:
/// 1. Normalize the query: lowercase, strip punctuation, split on
///    whitespace, drop stopwords.
/// 2. For each [Talk] in [talks], compute a weighted exact-token-membership
///    score: title tokens x3, speaker-name tokens x2, track/day label
///    tokens x1, abstract tokens x1.
/// 3. Drop talks with a score of zero.
/// 4. Sort remaining talks by [RetrievedTalk.score] desc, then
///    [RetrievedTalk.titleMatchCount] desc, then `Talk.startTime` asc, then
///    `Talk.id` asc (see `RetrievedTalk`'s doc comment for why this full
///    tie-break chain matters).
/// 5. Return the top 3.
///
/// A [query] that matches nothing MUST return an empty list (never throw,
/// never fall back to unrelated talks) — `BuildChatPromptUseCase` is
/// responsible for turning an empty result into an explicit "no matching
/// talk" instruction to the model, so this use case does not need to know
/// about prompting at all.
class RetrieveRelevantTalksUseCase {
  const RetrieveRelevantTalksUseCase();

  static const int _maxResults = 3;

  /// Common English words dropped from the normalized query before
  /// scoring — mostly question words, articles, prepositions, and
  /// conversational filler that would otherwise (a) never usefully match a
  /// talk's content and (b) risk spuriously matching a talk's own text
  /// (e.g. "the", "is") if left in.
  static const Set<String> _stopwords = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'was',
    'were',
    'be',
    'been',
    'being',
    'in',
    'on',
    'at',
    'to',
    'of',
    'for',
    'and',
    'or',
    'but',
    'with',
    'about',
    'what',
    'which',
    'who',
    'whom',
    'whose',
    'when',
    'where',
    'why',
    'how',
    'this',
    'that',
    'these',
    'those',
    'do',
    'does',
    'did',
    'tell',
    'me',
    'can',
    'could',
    'would',
    'should',
    'will',
    'shall',
    'i',
    'you',
    'it',
    'there',
    'any',
    'some',
    'please',
    'give',
    'show',
    'us',
    'my',
    'your',
  };

  /// Returns the top matches for [query] against [talks], most relevant
  /// first. See the class doc comment for the exact scoring/tie-break
  /// algorithm.
  List<RetrievedTalk> call({required String query, required List<Talk> talks}) {
    final queryTokens = _normalize(query);
    if (queryTokens.isEmpty) return const [];

    final scored = <RetrievedTalk>[];
    for (final talk in talks) {
      final titleTokens = _normalize(talk.title);
      final speakerTokens = _normalize(
        talk.speakers.map((s) => s.name).join(' '),
      );
      final trackDayTokens = _normalize(
        '${talk.track.label} ${talk.day.label}',
      );
      final abstractTokens = _normalize(talk.abstract);

      var score = 0;
      var titleMatchCount = 0;
      for (final token in queryTokens) {
        if (titleTokens.contains(token)) {
          score += 3;
          titleMatchCount++;
        }
        if (speakerTokens.contains(token)) score += 2;
        if (trackDayTokens.contains(token)) score += 1;
        if (abstractTokens.contains(token)) score += 1;
      }

      if (score > 0) {
        scored.add(
          RetrievedTalk(
            talk: talk,
            score: score,
            titleMatchCount: titleMatchCount,
          ),
        );
      }
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byTitleMatches = b.titleMatchCount.compareTo(a.titleMatchCount);
      if (byTitleMatches != 0) return byTitleMatches;
      final byStartTime = a.talk.startTime.compareTo(b.talk.startTime);
      if (byStartTime != 0) return byStartTime;
      return a.talk.id.compareTo(b.talk.id);
    });

    return scored.take(_maxResults).toList(growable: false);
  }

  /// Lowercase, strip punctuation, split on whitespace, drop stopwords.
  Set<String> _normalize(String text) {
    final stripped = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return stripped
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_stopwords.contains(token))
        .toSet();
  }
}
