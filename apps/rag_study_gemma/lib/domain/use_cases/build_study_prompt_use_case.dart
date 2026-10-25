import '../models/document_chunk.dart';
import '../models/retrieved_chunk.dart';
import '../models/study_document.dart';

/// Builds a bilingual-aware, citation-grounded prompt for Gemma 3 1B IT.
class BuildStudyPromptUseCase {
  const BuildStudyPromptUseCase();

  static const int defaultMaxExcerptChars = 520;

  static final RegExp _nonWhitespaceTokenPattern = RegExp(r'\S+');
  static final RegExp _encodedSealCharPattern = RegExp(r'[0-9+/=|]');
  static final RegExp _horizontalWhitespacePattern = RegExp(r'[ \t]+');
  static final RegExp _multiSpacePattern = RegExp(r'\s+');
  static final RegExp _nonAlphanumericPattern = RegExp(r'[^a-z0-9]');
  static final RegExp _sentenceEndingPattern = RegExp(r'[.!?](?=\s|$)');
  static final RegExp _trailingIncompleteLabelPattern = RegExp(
    r'\bForma\s+de\s*$',
    caseSensitive: false,
  );
  static final RegExp _boilerplateSealHeaderPattern = RegExp(
    r'(Cadena Original del Complemento de Certificaci[oó]n Digital del SAT|'
    r'Sello Digital del CFDI|'
    r'Sello del SAT|'
    r'ESTE DOCUMENTO ES UNA REPRESENTACI[OÓ]N IMPRESA DE UN CFDI)',
    caseSensitive: false,
  );

  String call({
    required String userQuestion,
    required List<RetrievedChunk> retrievedChunks,
    List<StudyDocument> availableDocuments = const [],
    int maxExcerptChars = defaultMaxExcerptChars,
  }) {
    final buffer = StringBuffer()
      ..writeln('You are StudyGemma, an expert on-device AI study companion.')
      ..writeln(
        "Detect the language of the student's question and ALWAYS reply in that exact same language (Spanish if asked in Spanish, English if asked in English).",
      )
      ..writeln(
        'Answer strictly using the provided PDF excerpts below. Every factual claim MUST cite the document title and page number using the format [Doc Title, p. X].',
      )
      ..writeln(
        'Synthesize the information into 3 to 5 complete, well-formed bullet points. Do NOT copy raw lines verbatim and NEVER leave a sentence or phrase incomplete (such as ending at a label with no value). Never repeat the same sentence, phrase, or bullet point. Stop immediately once you have answered the question.',
      )
      ..writeln(
        'If the answer is not contained in the provided PDF excerpts, state clearly that the information was not found in the study documents and do not invent facts.',
      )
      ..writeln();

    final selectedChunks = selectBestChunks(retrievedChunks);

    if (selectedChunks.isEmpty) {
      buffer.writeln('=== RETRIEVED PDF EXCERPTS ===');
      buffer.writeln('No matching excerpts were found in the indexed PDFs.');
      if (availableDocuments.isNotEmpty) {
        final titles = availableDocuments.map((d) => d.title).join(', ');
        buffer.writeln('Available Library Documents: $titles');
      }
      buffer.writeln();
    } else {
      buffer.writeln('=== RETRIEVED PDF EXCERPTS ===');
      for (var i = 0; i < selectedChunks.length; i++) {
        final chunk = selectedChunks[i].chunk;
        final rawExcerpt = chunk.content;
        if (rawExcerpt.isEmpty) continue;

        final sourceIndex = i + 1;
        final excerpt = _truncateAtWordBoundary(rawExcerpt, maxExcerptChars);
        buffer
          ..writeln(
            '[Source $sourceIndex | Document: ${chunk.docTitle} | Page ${chunk.pageNumber}]',
          )
          ..writeln(excerpt)
          ..writeln();
      }
    }

    buffer
      ..writeln('=== STUDENT QUESTION ===')
      ..writeln(userQuestion.trim());

    return buffer.toString().trim();
  }

  /// Selects up to [maxChunks] high-signal, non-redundant chunks for both UI
  /// citations and LLM prompt context:
  /// - Strips cryptographic seals and SAT chains via [sanitizeExcerpt].
  /// - Drops seal-only chunks when substantive chunks (`>= 100` chars) exist.
  /// - Drops short overlap fragments whose text is already contained inside a
  ///   longer candidate chunk.
  /// - Sorts selected chunks in natural reading order `(pageNumber, chunkIndex)`.
  /// - Trims repeated multi-page headers when the remaining suffix is
  ///   substantive (`>= 80` chars), or drops near-duplicate chunks.
  List<RetrievedChunk> selectBestChunks(
    List<RetrievedChunk> candidates, {
    int maxChunks = 3,
  }) {
    if (candidates.isEmpty) return const [];

    final sanitizedCandidates = <({_SanitizedCandidate item, int order})>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final cleaned = sanitizeExcerpt(candidate.chunk.content);
      if (cleaned.isEmpty) continue;

      final substantive = cleaned
          .replaceAll(_boilerplateSealHeaderPattern, '')
          .replaceAll(_multiSpacePattern, ' ')
          .trim();

      sanitizedCandidates.add((
        item: _SanitizedCandidate(
          retrieved: candidate,
          cleanedContent: cleaned,
          substantiveLength: substantive.length,
        ),
        order: i,
      ));
    }

    if (sanitizedCandidates.isEmpty) return const [];

    final hasSubstantiveChunk = sanitizedCandidates.any(
      (entry) => entry.item.substantiveLength >= 100,
    );

    final afterSealFilter = hasSubstantiveChunk
        ? sanitizedCandidates
              .where((entry) => entry.item.substantiveLength >= 100)
              .toList()
        : sanitizedCandidates;

    final nonSubstringCandidates = <_SanitizedCandidate>[];
    for (var i = 0; i < afterSealFilter.length; i++) {
      final current = afterSealFilter[i].item;
      var isContainedInLonger = false;
      for (var j = 0; j < afterSealFilter.length; j++) {
        if (i == j) continue;
        final other = afterSealFilter[j].item;
        if (other.cleanedContent.length > current.cleanedContent.length &&
            other.cleanedContent.contains(current.cleanedContent)) {
          isContainedInLonger = true;
          break;
        }
      }
      if (!isContainedInLonger) {
        nonSubstringCandidates.add(current);
      }
    }

    nonSubstringCandidates.sort((a, b) {
      final docCompare = a.retrieved.chunk.docId.compareTo(
        b.retrieved.chunk.docId,
      );
      if (docCompare != 0) return docCompare;
      final pageCompare = a.retrieved.chunk.pageNumber.compareTo(
        b.retrieved.chunk.pageNumber,
      );
      if (pageCompare != 0) return pageCompare;
      return a.retrieved.chunk.chunkIndex.compareTo(
        b.retrieved.chunk.chunkIndex,
      );
    });

    final selected = <RetrievedChunk>[];
    final seenFullTexts = <String>[];
    final seenFingerprints = <String>{};

    for (final candidate in nonSubstringCandidates) {
      var effectiveText = candidate.cleanedContent;
      var dropAsDuplicate = false;

      for (final previousText in seenFullTexts) {
        final sharedPrefixLen = _sharedPrefixLength(
          previousText,
          effectiveText,
        );
        if (sharedPrefixLen >= 80) {
          final remainder = effectiveText.substring(sharedPrefixLen).trim();
          if (remainder.length < 80) {
            dropAsDuplicate = true;
            break;
          } else {
            effectiveText = remainder;
          }
        }
      }

      if (dropAsDuplicate || effectiveText.isEmpty) continue;

      final fingerprint = _excerptFingerprint(effectiveText);
      if (seenFullTexts.contains(effectiveText) ||
          (fingerprint.length >= 30 &&
              seenFingerprints.contains(fingerprint))) {
        continue;
      }

      seenFullTexts.add(candidate.cleanedContent);
      seenFullTexts.add(effectiveText);
      if (fingerprint.length >= 30) {
        seenFingerprints.add(fingerprint);
      }

      final sourceChunk = candidate.retrieved.chunk;
      selected.add(
        RetrievedChunk(
          chunk: DocumentChunk(
            id: sourceChunk.id,
            docId: sourceChunk.docId,
            docTitle: sourceChunk.docTitle,
            pageNumber: sourceChunk.pageNumber,
            chunkIndex: sourceChunk.chunkIndex,
            content: effectiveText,
          ),
          similarityScore: candidate.retrieved.similarityScore,
        ),
      );

      if (selected.length >= maxChunks) break;
    }

    return selected;
  }

  /// Strips `>= 48`-char machine-encoded tokens (Base64 seals, SAT pipes),
  /// collapses horizontal whitespace while preserving `\n` line breaks, and
  /// trims dangling cut-off `"Forma de"` labels.
  String sanitizeExcerpt(String raw) {
    if (raw.isEmpty) return '';
    final unixNewlines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final cleanedLines = <String>[];
    for (final rawLine in unixNewlines.split('\n')) {
      final replaced = rawLine.replaceAllMapped(_nonWhitespaceTokenPattern, (
        match,
      ) {
        final token = match.group(0)!;
        if (token.length >= 48 && _encodedSealCharPattern.hasMatch(token)) {
          return '';
        }
        return token;
      });
      final collapsed = replaced
          .replaceAll(_horizontalWhitespacePattern, ' ')
          .trim()
          .replaceFirst(_trailingIncompleteLabelPattern, '')
          .trim();
      if (collapsed.isNotEmpty) {
        cleanedLines.add(collapsed);
      }
    }
    return cleanedLines.join('\n');
  }

  String _truncateAtWordBoundary(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final minCut = maxChars ~/ 2;
    final window = text.substring(0, maxChars);

    final lastNewline = window.lastIndexOf('\n');
    if (lastNewline >= minCut) {
      return window
          .substring(0, lastNewline)
          .trimRight()
          .replaceFirst(_trailingIncompleteLabelPattern, '')
          .trimRight();
    }

    var lastSentenceEnd = -1;
    for (final match in _sentenceEndingPattern.allMatches(window)) {
      if (match.end >= minCut) {
        lastSentenceEnd = match.end;
      }
    }
    if (lastSentenceEnd >= minCut) {
      return window
          .substring(0, lastSentenceEnd)
          .trimRight()
          .replaceFirst(_trailingIncompleteLabelPattern, '')
          .trimRight();
    }

    final cut = text.lastIndexOf(' ', maxChars);
    final truncated = cut > minCut
        ? text.substring(0, cut).trimRight()
        : window;
    final cleanedTruncated = truncated
        .replaceFirst(_trailingIncompleteLabelPattern, '')
        .trimRight();
    return '$cleanedTruncated...';
  }

  int _sharedPrefixLength(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < minLen && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    if (i < minLen && i > 0) {
      final prevUnit = a.codeUnitAt(i - 1);
      if (prevUnit != 0x20 && prevUnit != 0x0A) {
        final lastSpace = a.lastIndexOf(' ', i - 1);
        final lastNewline = a.lastIndexOf('\n', i - 1);
        final lastBoundary = lastSpace > lastNewline ? lastSpace : lastNewline;
        if (lastBoundary != -1) {
          return lastBoundary + 1;
        }
      }
    }
    return i;
  }

  String _excerptFingerprint(String sanitizedExcerpt) {
    final alnum = sanitizedExcerpt.toLowerCase().replaceAll(
      _nonAlphanumericPattern,
      '',
    );
    return alnum.length > 100 ? alnum.substring(0, 100) : alnum;
  }
}

class _SanitizedCandidate {
  const _SanitizedCandidate({
    required this.retrieved,
    required this.cleanedContent,
    required this.substantiveLength,
  });

  final RetrievedChunk retrieved;
  final String cleanedContent;
  final int substantiveLength;
}
