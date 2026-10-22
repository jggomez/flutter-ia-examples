import 'package:flutter/material.dart';

import '../../../domain/models/citation.dart';

/// A modern, tappable pill rendering one [Citation] under an assistant chat reply.
///
/// Features an [Icons.event_note_rounded] leading icon, subtle container background,
/// and smooth tap feedback navigating to `TalkDetailScreen`.
class CitationChip extends StatelessWidget {
  const CitationChip({super.key, required this.citation, required this.onTap});

  final Citation citation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ActionChip(
      avatar: Icon(
        Icons.event_note_rounded,
        size: 16,
        color: colorScheme.primary,
      ),
      label: Text(
        citation.talkTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest.withAlpha(180),
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onPressed: onTap,
    );
  }
}
