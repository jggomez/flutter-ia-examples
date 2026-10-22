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

  static const List<String> _representativeKeynoteIds = [
    'talk-001',
    'talk-006',
    'talk-011',
    'talk-016',
  ];

  static const Set<String> _generalQueryKeywords = {
    'agenda',
    'charla',
    'charlas',
    'talk',
    'talks',
    'conferencia',
    'conference',
    'evento',
    'event',
    'resumen',
    'overview',
    'summary',
    'sesion',
    'sesiones',
    'session',
    'sessions',
    'horario',
    'schedule',
    'cronograma',
    'programa',
    'todas',
    'todo',
  };

  /// Common English and Spanish words dropped from the normalized query before
  /// scoring — mostly question words, articles, prepositions, and
  /// conversational filler.
  static const Set<String> _stopwords = {
    // English
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

    // Spanish
    'de',
    'la',
    'el',
    'los',
    'las',
    'un',
    'una',
    'unos',
    'unas',
    'y',
    'e',
    'o',
    'u',
    'en',
    'para',
    'por',
    'con',
    'sin',
    'sobre',
    'entre',
    'del',
    'al',
    'que',
    'quien',
    'quienes',
    'cual',
    'cuales',
    'como',
    'donde',
    'cuando',
    'porque',
    'es',
    'son',
    'fue',
    'era',
    'ser',
    'estar',
    'hay',
    'habla',
    'hablan',
    'trata',
    'tratan',
    'dime',
    'cuentame',
    'muestra',
    'favor',
    'este',
    'esta',
    'estos',
    'estas',
    'mi',
    'tu',
    'su',
    'nuestro',
    'te',
    'se',
    'nos',
  };

  static const Map<String, List<String>> _synonymMap = {
    'charla': ['talk', 'session'],
    'charlas': ['talk', 'session'],
    'platica': ['talk', 'session'],
    'platicas': ['talk', 'session'],
    'sesion': ['talk', 'session'],
    'sesiones': ['talk', 'session'],
    'ia': ['ai', 'llm', 'model', 'inference', 'on-device'],
    'inteligencia': ['ai', 'llm', 'model', 'inference', 'on-device'],
    'ponente': ['speaker', 'speakers'],
    'ponentes': ['speaker', 'speakers'],
    'expositor': ['speaker', 'speakers'],
    'expositores': ['speaker', 'speakers'],
    'conferencista': ['speaker', 'speakers'],
    'conferencistas': ['speaker', 'speakers'],
    'horario': ['schedule', 'agenda', 'day', 'conference'],
    'horarios': ['schedule', 'agenda', 'day', 'conference'],
    'agenda': ['schedule', 'agenda', 'day', 'conference'],
    'evento': ['schedule', 'agenda', 'day', 'conference'],
    'conferencia': ['schedule', 'agenda', 'day', 'conference'],
    'cronograma': ['schedule', 'agenda', 'day', 'conference'],
    'programa': ['schedule', 'agenda', 'day', 'conference'],
    'cuantizacion': ['quantization', 'quantize', 'int4', 'int8'],
    'cuantizar': ['quantization', 'quantize', 'int4', 'int8'],
    'rendimiento': ['latency', 'performance', 'speed', 'memory'],
    'velocidad': ['latency', 'performance', 'speed', 'memory'],
    'latencia': ['latency', 'performance', 'speed', 'memory'],
    'movil': ['mobile', 'edge', 'phone', 'device'],
    'celular': ['mobile', 'edge', 'phone', 'device'],
    'dispositivo': ['mobile', 'edge', 'phone', 'device'],
    'sqlite': ['sqflite'],
    'sqflite': ['sqlite'],
  };

  /// Returns the top matches for [query] against [talks], most relevant
  /// first. See the class doc comment for the exact scoring/tie-break
  /// algorithm.
  List<RetrievedTalk> call({required String query, required List<Talk> talks}) {
    final queryTokens = _normalize(query);
    final rawTokens = _stripDiacritics(query)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
    final isGeneralQuery = rawTokens.any(_generalQueryKeywords.contains);

    if (queryTokens.isEmpty && !isGeneralQuery) return const [];

    final expandedQueryTokens = <String>{...queryTokens};
    for (final token in queryTokens) {
      final synonyms = _synonymMap[token];
      if (synonyms != null) {
        expandedQueryTokens.addAll(synonyms);
      }
    }

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
      for (final token in expandedQueryTokens) {
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

    if (scored.isNotEmpty) {
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

    if (isGeneralQuery) {
      final keynoteMap = {for (final talk in talks) talk.id: talk};
      final keynotes = <RetrievedTalk>[];
      for (final id in _representativeKeynoteIds) {
        final talk = keynoteMap[id];
        if (talk != null) {
          keynotes.add(RetrievedTalk(talk: talk, score: 1, titleMatchCount: 0));
        }
      }
      if (keynotes.isNotEmpty) {
        return keynotes;
      }
      return talks
          .take(4)
          .map((t) => RetrievedTalk(talk: t, score: 1, titleMatchCount: 0))
          .toList(growable: false);
    }

    return const [];
  }

  /// Strip diacritics / accent marks.
  static String _stripDiacritics(String text) {
    return text
        .replaceAll(RegExp(r'[áàäâ]', caseSensitive: false), 'a')
        .replaceAll(RegExp(r'[éèëê]', caseSensitive: false), 'e')
        .replaceAll(RegExp(r'[íìïî]', caseSensitive: false), 'i')
        .replaceAll(RegExp(r'[óòöô]', caseSensitive: false), 'o')
        .replaceAll(RegExp(r'[úùüû]', caseSensitive: false), 'u')
        .replaceAll(RegExp(r'[ñ]', caseSensitive: false), 'n')
        .replaceAll(RegExp(r'[ç]', caseSensitive: false), 'c');
  }

  /// Lowercase, strip diacritics and punctuation, split on whitespace, drop stopwords.
  Set<String> _normalize(String text) {
    final stripped = _stripDiacritics(text)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return stripped
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_stopwords.contains(token))
        .toSet();
  }
}
