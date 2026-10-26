import 'package:flutter/material.dart';

import '../theme/pocket_squad_theme.dart';

/// Represents a distinct single-agent segment extracted from a potentially
/// multi-agent concatenated ADK turn response.
class AgentMessageSection {
  const AgentMessageSection({required this.author, required this.content});

  final String author;
  final String content;
}

/// Renders agent responses and travel dossier artifacts as clean, native
/// Flutter typography blocks (headings, day pills, Markdown tables, bullets,
/// numbered lists, bold/italic/code spans) with zero raw Markdown symbols.
class FormattedAgentMessageView extends StatelessWidget {
  const FormattedAgentMessageView({
    super.key,
    required this.text,
    this.accentColor = PocketSquadTheme.sunsetAmber,
    this.maxBlocks,
  });

  final String text;
  final Color accentColor;
  final int? maxBlocks;

  static const Color _silkIvory = Color(0xFFF8FAFC);

  static final RegExp _agentBannerLinePattern = RegExp(
    r'^\s*#{1,6}\s*(?:🎯|🧭|💰|✨|🛎️)?\s*(?:CoordinatorAgent|ScoutAgent|BudgetAuditorAgent|ConciergeAgent|Stage\s*[123]\b)[^\n]*$',
    multiLine: true,
    caseSensitive: false,
  );

  static final RegExp _headingPattern = RegExp(r'^\s*#{1,6}\s+(.+)$');
  static final RegExp _dayTitlePattern = RegExp(
    r'^(?:d[íi]a|day)\s*\d+\b',
    caseSensitive: false,
  );
  static final RegExp _hrPattern = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
  static final RegExp _bulletPattern = RegExp(r'^(\s*)(?:[-*•])\s+(.+)$');
  static final RegExp _numberedPattern = RegExp(r'^(\s*)(\d+\.)\s+(.+)$');
  static final RegExp _tableSeparatorPattern = RegExp(
    r'^\s*\|?(?:\s*:?-{2,}:?\s*\|)+\s*:?-{2,}:?\s*\|?\s*$',
  );
  static final RegExp _inlineSpanPattern = RegExp(
    r'\*\*(.+?)\*\*|`([^`]+)`|\*([^*]+)\*',
  );

  /// Splits a raw ADK turn string into chronological [AgentMessageSection]
  /// blocks whenever internal agent banners (`### 🎯 CoordinatorAgent...`,
  /// `### 🧭 ScoutAgent...`, `### 💰 BudgetAuditorAgent...`,
  /// `### ✨ ConciergeAgent...`) are present.
  static List<AgentMessageSection> splitAgentSections(
    String rawText, {
    required String fallbackAuthor,
  }) {
    if (rawText.trim().isEmpty) {
      return const <AgentMessageSection>[];
    }

    final normalizedFallback = fallbackAuthor.trim().isNotEmpty
        ? fallbackAuthor.trim()
        : 'agent';
    final lines = rawText.split('\n');
    final sections = <AgentMessageSection>[];

    String? currentAuthor;
    final buffer = <String>[];

    void flushCurrent() {
      final content = cleanRawAgentHeaders(buffer.join('\n'));
      buffer.clear();
      if (content.isNotEmpty) {
        sections.add(
          AgentMessageSection(
            author: currentAuthor ?? normalizedFallback,
            content: content,
          ),
        );
      }
    }

    for (final line in lines) {
      final detectedAuthor = _detectBannerAuthor(line);
      if (detectedAuthor != null) {
        flushCurrent();
        currentAuthor = detectedAuthor;
        continue;
      }
      buffer.add(line);
    }
    flushCurrent();

    if (sections.isEmpty) {
      final cleaned = cleanRawAgentHeaders(rawText);
      if (cleaned.isNotEmpty) {
        return <AgentMessageSection>[
          AgentMessageSection(author: normalizedFallback, content: cleaned),
        ];
      }
    }

    return sections;
  }

  static String? _detectBannerAuthor(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#')) return null;
    final lower = trimmed.toLowerCase();
    if (lower.contains('coordinatoragent')) {
      return 'coordinator_agent';
    }
    if (lower.contains('scoutagent') || lower.contains('stage 1')) {
      return 'scout_agent';
    }
    if (lower.contains('budgetauditoragent') || lower.contains('stage 2')) {
      return 'budget_auditor_agent';
    }
    if (lower.contains('conciergeagent') || lower.contains('stage 3')) {
      return 'concierge_agent';
    }
    return null;
  }

  /// Strips internal `### 🎯 CoordinatorAgent — ...` section banners that
  /// duplicate the message card's role badge.
  static String cleanRawAgentHeaders(String raw) {
    if (raw.trim().isEmpty) return '';
    return raw
        .replaceAll(_agentBannerLinePattern, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Strips Markdown markers (`###`, `**`, `` ` ``) for single-line log previews.
  static String toPlainPreview(String raw) {
    final cleaned = cleanRawAgentHeaders(raw);
    return cleaned
        .replaceAll(RegExp(r'^\s*#{1,6}\s+', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceAll('|', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleaned = cleanRawAgentHeaders(text);
    if (cleaned.isEmpty) {
      return const SizedBox.shrink();
    }

    final rawLines = cleaned.split('\n');
    final widgets = <Widget>[];
    var blockCount = 0;

    for (var i = 0; i < rawLines.length; i++) {
      if (maxBlocks != null && blockCount >= maxBlocks!) {
        break;
      }

      final line = rawLines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (widgets.isNotEmpty && widgets.last is! SizedBox) {
          widgets.add(const SizedBox(height: 6));
        }
        continue;
      }

      if (_hrPattern.hasMatch(trimmed)) {
        widgets.add(
          const Divider(height: 14, color: PocketSquadTheme.obsidianBorder),
        );
        blockCount++;
        continue;
      }

      // Markdown table row or separator (`| ... |`)
      if (_isMarkdownTableLine(trimmed)) {
        if (_tableSeparatorPattern.hasMatch(trimmed)) {
          continue;
        }
        final cells = _extractTableCells(trimmed);
        if (cells.isNotEmpty) {
          widgets.add(_buildTableRowBlock(theme, cells));
          blockCount++;
          continue;
        }
      }

      final headingMatch = _headingPattern.firstMatch(line);
      if (headingMatch != null) {
        final headingText = headingMatch
            .group(1)!
            .replaceAll('**', '')
            .replaceAll('`', '')
            .trim();
        if (headingText.isNotEmpty) {
          if (widgets.isNotEmpty) {
            widgets.add(const SizedBox(height: 6));
          }
          if (_dayTitlePattern.hasMatch(headingText)) {
            widgets.add(_buildDayHeaderBlock(theme, headingText));
          } else {
            widgets.add(_buildHeadingBlock(theme, headingText));
          }
          widgets.add(const SizedBox(height: 4));
          blockCount++;
        }
        continue;
      }

      // Standalone Day line without `#` (e.g., `**Día 1: Centro Histórico**`)
      final strippedForDayCheck = trimmed.replaceAll('**', '').trim();
      if (_dayTitlePattern.hasMatch(strippedForDayCheck)) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 6));
        }
        widgets.add(_buildDayHeaderBlock(theme, strippedForDayCheck));
        widgets.add(const SizedBox(height: 4));
        blockCount++;
        continue;
      }

      final bulletMatch = _bulletPattern.firstMatch(line);
      if (bulletMatch != null) {
        final indentSpaces = bulletMatch.group(1)?.length ?? 0;
        final bulletContent = bulletMatch.group(2)!.trim();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              left: indentSpaces > 1 ? 12.0 : 0.0,
              bottom: 4.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: _buildInlineRichText(theme, bulletContent)),
              ],
            ),
          ),
        );
        blockCount++;
        continue;
      }

      final numberedMatch = _numberedPattern.firstMatch(line);
      if (numberedMatch != null) {
        final indentSpaces = numberedMatch.group(1)?.length ?? 0;
        final numberLabel = numberedMatch.group(2)!;
        final itemContent = numberedMatch.group(3)!.trim();
        widgets.add(
          Padding(
            padding: EdgeInsets.only(
              left: indentSpaces > 1 ? 12.0 : 0.0,
              bottom: 4.0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 1),
                  child: Text(
                    numberLabel,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
                Expanded(child: _buildInlineRichText(theme, itemContent)),
              ],
            ),
          ),
        );
        blockCount++;
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildInlineRichText(theme, trimmed),
        ),
      );
      blockCount++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  static bool _isMarkdownTableLine(String trimmed) {
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      return true;
    }
    final pipeCount = '|'.allMatches(trimmed).length;
    return pipeCount >= 2 && trimmed.startsWith('|');
  }

  static List<String> _extractTableCells(String trimmed) {
    var parts = trimmed.split('|').map((cell) => cell.trim()).toList();
    if (parts.isNotEmpty && parts.first.isEmpty) {
      parts = parts.sublist(1);
    }
    if (parts.isNotEmpty && parts.last.isEmpty) {
      parts = parts.sublist(0, parts.length - 1);
    }
    return parts
        .map(
          (cell) => cell
              .replaceAll('**', '')
              .replaceAll('`', '')
              .replaceAll('###', '')
              .trim(),
        )
        .where((cell) => cell.isNotEmpty)
        .toList();
  }

  Widget _buildTableRowBlock(ThemeData theme, List<String> cells) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PocketSquadTheme.obsidianDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: PocketSquadTheme.obsidianBorder.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < cells.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              flex: i == 0 ? 3 : 2,
              child: Text(
                cells[i],
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                  color: i == 0 ? _silkIvory : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayHeaderBlock(ThemeData theme, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.place_rounded, size: 15, color: accentColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _silkIvory,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeadingBlock(ThemeData theme, String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: _silkIvory,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineRichText(ThemeData theme, String content) {
    final baseStyle =
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 1.45,
          color: theme.colorScheme.onSurface,
        ) ??
        const TextStyle(fontSize: 13, height: 1.45, color: _silkIvory);

    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _inlineSpanPattern.allMatches(content)) {
      if (match.start > cursor) {
        final plainSegment = _sanitizeResidualMarkers(
          content.substring(cursor, match.start),
        );
        if (plainSegment.isNotEmpty) {
          spans.add(TextSpan(text: plainSegment, style: baseStyle));
        }
      }

      final boldGroup = match.group(1);
      final codeGroup = match.group(2);
      final italicGroup = match.group(3);

      if (boldGroup != null) {
        spans.add(
          TextSpan(
            text: _sanitizeResidualMarkers(boldGroup),
            style: baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              color: _silkIvory,
            ),
          ),
        );
      } else if (codeGroup != null) {
        spans.add(
          TextSpan(
            text: codeGroup,
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PocketSquadTheme.sunsetAmberSoft,
            ),
          ),
        );
      } else if (italicGroup != null) {
        spans.add(
          TextSpan(
            text: _sanitizeResidualMarkers(italicGroup),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < content.length) {
      final tail = _sanitizeResidualMarkers(content.substring(cursor));
      if (tail.isNotEmpty) {
        spans.add(TextSpan(text: tail, style: baseStyle));
      }
    }

    if (spans.isEmpty) {
      return Text(_sanitizeResidualMarkers(content), style: baseStyle);
    }

    return Text.rich(TextSpan(children: spans));
  }

  static String _sanitizeResidualMarkers(String input) {
    return input.replaceAll('**', '').replaceAll('###', '');
  }
}
