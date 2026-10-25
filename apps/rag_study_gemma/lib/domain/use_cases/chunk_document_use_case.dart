import 'dart:math' as math;

import '../models/document_chunk.dart';
import '../models/extracted_pdf_page.dart';

/// Pure-Dart structure-aware sliding-window chunker for extracted PDF pages.
///
/// Preserves `\n` line breaks and chunks along complete line (`\n`) or
/// sentence (`.`, `!`, `?`) boundaries so chunks never end mid-phrase.
class ChunkDocumentUseCase {
  const ChunkDocumentUseCase();

  static final RegExp _hyphenatedLineBreakPattern = RegExp(
    r'[-\u00AD\u2010-\u2015]\n[ \t]*',
  );
  static final RegExp _softHyphenPattern = RegExp(r'\u00AD');
  static final RegExp _horizontalWhitespacePattern = RegExp(r'[ \t]+');
  static final RegExp _whitespaceRunPattern = RegExp(r'\s+');
  static final RegExp _nonWhitespaceTokenPattern = RegExp(r'\S+');
  static final RegExp _sentenceBoundaryPattern = RegExp(r'(?<=[.!?])\s+');
  static final RegExp _sentenceTerminalPattern = RegExp(r'[.!?:;]$');
  static final RegExp _startsWithLowercasePattern = RegExp(r'^[a-záéíóúüñ,]');
  static final RegExp _sealSpecialCharPattern = RegExp(r'[+/=|]');
  static final RegExp _upperCasePattern = RegExp(r'[A-Z]');
  static final RegExp _lowerCasePattern = RegExp(r'[a-z]');
  static final RegExp _digitPattern = RegExp(r'[0-9]');

  List<DocumentChunk> call({
    required String docId,
    required String docTitle,
    required List<ExtractedPdfPage> pages,
    int targetWords = 220,
    int overlapWords = 40,
    int maxChars = 1400,
  }) {
    final chunks = <DocumentChunk>[];
    final effectiveTargetWords = math.max(1, targetWords);
    final effectiveOverlapWords = overlapWords.clamp(
      0,
      effectiveTargetWords - 1,
    );

    for (final page in pages) {
      final normalized = _normalizePageText(page.text);
      if (normalized.isEmpty) continue;

      final pageSegments = _chunkNormalizedPage(
        normalizedText: normalized,
        effectiveTargetWords: effectiveTargetWords,
        effectiveOverlapWords: effectiveOverlapWords,
        maxChars: maxChars,
      );

      for (var chunkIndex = 0; chunkIndex < pageSegments.length; chunkIndex++) {
        chunks.add(
          DocumentChunk(
            id: '${docId}_p${page.pageNumber}_c$chunkIndex',
            docId: docId,
            docTitle: docTitle,
            pageNumber: page.pageNumber,
            chunkIndex: chunkIndex,
            content: pageSegments[chunkIndex],
          ),
        );
      }
    }

    return chunks;
  }

  String _normalizePageText(String rawText) {
    if (rawText.isEmpty) return '';
    final unixNewlines = rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final dehyphenated = unixNewlines
        .replaceAll(_hyphenatedLineBreakPattern, '')
        .replaceAll(_softHyphenPattern, '');

    final rawLines = dehyphenated.split('\n');
    final cleanedEntries = <({String text, bool precededByBlankLine})>[];
    var sawBlankLine = false;

    for (final rawLine in rawLines) {
      final withoutSeals = rawLine.replaceAllMapped(
        _nonWhitespaceTokenPattern,
        (match) {
          final token = match.group(0)!;
          return _isMachineEncodedSealToken(token) ? '' : token;
        },
      );
      final collapsed = withoutSeals
          .replaceAll(_horizontalWhitespacePattern, ' ')
          .trim();
      if (collapsed.isEmpty) {
        if (cleanedEntries.isNotEmpty) {
          sawBlankLine = true;
        }
      } else {
        cleanedEntries.add((
          text: collapsed,
          precededByBlankLine: sawBlankLine,
        ));
        sawBlankLine = false;
      }
    }

    if (cleanedEntries.isEmpty) return '';

    final mergedLines = <String>[];
    var current = cleanedEntries.first.text;

    for (var i = 1; i < cleanedEntries.length; i++) {
      final next = cleanedEntries[i];
      final currentEndsWithTerminal = _sentenceTerminalPattern.hasMatch(
        current,
      );
      final currentIsKeyValueLine = current.contains(':');
      final currentWordCount = _countWords(current);
      final nextStartsLower = _startsWithLowercasePattern.hasMatch(next.text);

      final shouldMergeSoftWrap =
          !currentEndsWithTerminal &&
          !currentIsKeyValueLine &&
          (currentWordCount > 8 ||
              (!next.precededByBlankLine && nextStartsLower));

      if (shouldMergeSoftWrap) {
        current = '$current ${next.text}';
      } else {
        mergedLines.add(current);
        current = next.text;
      }
    }
    mergedLines.add(current);

    return mergedLines.join('\n');
  }

  static bool _isMachineEncodedSealToken(String token) {
    if (token.length < 48) return false;
    if (_sealSpecialCharPattern.hasMatch(token)) return true;
    return _upperCasePattern.hasMatch(token) &&
        _lowerCasePattern.hasMatch(token) &&
        _digitPattern.hasMatch(token);
  }

  List<String> _chunkNormalizedPage({
    required String normalizedText,
    required int effectiveTargetWords,
    required int effectiveOverlapWords,
    required int maxChars,
  }) {
    final lines = normalizedText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    // Fast path for a single unpunctuated line that exceeds limits.
    if (lines.length == 1) {
      final singleLine = lines.first;
      final sentences = singleLine
          .split(_sentenceBoundaryPattern)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (sentences.length == 1 &&
          (_countWords(singleLine) > effectiveTargetWords ||
              singleLine.length > maxChars)) {
        return _chunkUnpunctuatedSegment(
          text: singleLine,
          effectiveTargetWords: effectiveTargetWords,
          effectiveOverlapWords: effectiveOverlapWords,
          maxChars: maxChars,
        );
      }
    }

    final joinWithNewline = lines.length > 1;
    final units = <_TextUnit>[];

    for (final line in lines) {
      final lineWords = _countWords(line);
      final isKeyValueLine = line.contains(':');
      final hasMultipleSentences =
          !isKeyValueLine && _sentenceBoundaryPattern.hasMatch(line);

      if (!hasMultipleSentences &&
          lineWords <= effectiveTargetWords &&
          line.length <= maxChars) {
        units.add(
          _TextUnit(
            text: line,
            wordCount: lineWords,
            joinWithNewline: joinWithNewline,
          ),
        );
      } else {
        final sentences = line
            .split(_sentenceBoundaryPattern)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final sentence in sentences) {
          final sentenceWords = _countWords(sentence);
          if (sentenceWords <= effectiveTargetWords &&
              sentence.length <= maxChars) {
            units.add(
              _TextUnit(
                text: sentence,
                wordCount: sentenceWords,
                joinWithNewline: joinWithNewline,
              ),
            );
          } else {
            final fallbackSegments = _chunkUnpunctuatedSegment(
              text: sentence,
              effectiveTargetWords: effectiveTargetWords,
              effectiveOverlapWords: 0,
              maxChars: maxChars,
            );
            for (final seg in fallbackSegments) {
              units.add(
                _TextUnit(
                  text: seg,
                  wordCount: _countWords(seg),
                  joinWithNewline: joinWithNewline,
                ),
              );
            }
          }
        }
      }
    }

    if (units.isEmpty) return const [];

    final pageSegments = <String>[];
    var startUnit = 0;

    while (startUnit < units.length) {
      final buffer = StringBuffer();
      var currentWords = 0;
      var endUnit = startUnit;

      while (endUnit < units.length) {
        final unit = units[endUnit];
        final sep = unit.joinWithNewline ? '\n' : ' ';
        final candidateLength = buffer.isEmpty
            ? unit.text.length
            : buffer.length + sep.length + unit.text.length;
        final candidateWords = currentWords + unit.wordCount;

        if (buffer.isNotEmpty &&
            (candidateWords > effectiveTargetWords ||
                candidateLength > maxChars)) {
          break;
        }

        if (buffer.isNotEmpty) {
          buffer.write(sep);
        }
        buffer.write(unit.text);
        currentWords = candidateWords;
        endUnit++;
      }

      pageSegments.add(buffer.toString());
      if (endUnit >= units.length) break;

      // Step back to include trailing complete units from this chunk that fit
      // within effectiveOverlapWords AND still leave room for units[endUnit].
      var nextStart = endUnit;
      var overlapOnlyWords = 0;
      var combinedWordsWithNext = units[endUnit].wordCount;
      var combinedCharsWithNext = units[endUnit].text.length;

      while (nextStart - 1 > startUnit) {
        final prev = units[nextStart - 1];
        if (overlapOnlyWords + prev.wordCount > effectiveOverlapWords) {
          break;
        }
        if (combinedWordsWithNext + prev.wordCount > effectiveTargetWords ||
            combinedCharsWithNext + 1 + prev.text.length > maxChars) {
          break;
        }
        overlapOnlyWords += prev.wordCount;
        combinedWordsWithNext += prev.wordCount;
        combinedCharsWithNext += 1 + prev.text.length;
        nextStart--;
      }

      startUnit = nextStart;
    }

    return pageSegments;
  }

  int _countWords(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(_whitespaceRunPattern).length;
  }

  List<String> _chunkUnpunctuatedSegment({
    required String text,
    required int effectiveTargetWords,
    required int effectiveOverlapWords,
    required int maxChars,
  }) {
    final words = _splitSafeWords(text, maxChars);
    if (words.isEmpty) return const [];

    final stepWords = math.max(1, effectiveTargetWords - effectiveOverlapWords);
    final segments = <String>[];
    var start = 0;

    while (start < words.length) {
      final end = math.min(start + effectiveTargetWords, words.length);
      final windowWords = words.sublist(start, end);
      segments.addAll(_enforceMaxCharsOnWindow(windowWords, maxChars));

      if (end >= words.length) break;
      start += stepWords;
    }

    return segments;
  }

  /// Splits normalized text into word tokens while slicing any single unbroken
  /// token longer than [maxChars] so no token ever exceeds [maxChars].
  List<String> _splitSafeWords(String normalizedText, int maxChars) {
    final rawWords = normalizedText.split(' ');
    final safeWords = <String>[];

    for (final word in rawWords) {
      if (word.isEmpty) continue;
      if (word.length <= maxChars) {
        safeWords.add(word);
      } else {
        for (var offset = 0; offset < word.length; offset += maxChars) {
          final sliceEnd = math.min(offset + maxChars, word.length);
          safeWords.add(word.substring(offset, sliceEnd));
        }
      }
    }

    return safeWords;
  }

  /// Ensures a word window never produces a string exceeding [maxChars].
  List<String> _enforceMaxCharsOnWindow(
    List<String> windowWords,
    int maxChars,
  ) {
    final joined = windowWords.join(' ');
    if (joined.length <= maxChars) {
      return [joined];
    }

    final segments = <String>[];
    final currentBuffer = StringBuffer();

    for (final word in windowWords) {
      if (currentBuffer.isEmpty) {
        currentBuffer.write(word);
      } else if (currentBuffer.length + 1 + word.length <= maxChars) {
        currentBuffer.write(' ');
        currentBuffer.write(word);
      } else {
        segments.add(currentBuffer.toString());
        currentBuffer.clear();
        currentBuffer.write(word);
      }
    }

    if (currentBuffer.isNotEmpty) {
      segments.add(currentBuffer.toString());
    }

    return segments;
  }
}

class _TextUnit {
  const _TextUnit({
    required this.text,
    required this.wordCount,
    required this.joinWithNewline,
  });

  final String text;
  final int wordCount;
  final bool joinWithNewline;
}
