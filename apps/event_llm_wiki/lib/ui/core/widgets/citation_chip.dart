import 'package:flutter/material.dart';

import '../../../domain/models/citation.dart';

/// A tappable chip rendering one [Citation] under an assistant chat reply.
///
/// Shared, feature-agnostic (used by `ui/features/chat/views/chat_screen.dart`
/// under each assistant `ChatMessage` that has citations); nothing here may
/// import from `ui/features/**`, `data/**`, or `domain/repositories/**` —
/// see `ui/core/theme/README.md` for the same rule applied to theming.
///
/// [onTap] is expected to be wired to navigation into
/// `ui/features/agenda/views/talk_detail_screen.dart` for
/// `citation.talkId` (via `TalkDetailViewModel.family`).
class CitationChip extends StatelessWidget {
  const CitationChip({super.key, required this.citation, required this.onTap});

  final Citation citation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.event_note, size: 18),
      label: Text(citation.talkTitle),
      onPressed: onTap,
    );
  }
}
