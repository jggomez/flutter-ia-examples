import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/conference_day.dart';
import '../../../../domain/models/speaker.dart';
import '../../../../domain/models/talk.dart';
import '../../../core/widgets/track_badge.dart';
import '../../chat/views/chat_tab_root.dart';
import '../view_models/talk_detail_view_model.dart';

/// Full detail view of a single talk: hero header, information ribbon,
/// speaker profile cards, session abstract, and an "Ask AI about this talk" CTA.
class TalkDetailScreen extends ConsumerWidget {
  const TalkDetailScreen({super.key, required this.talkId});

  final String talkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(talkDetailViewModelProvider(talkId));
    return Scaffold(
      appBar: AppBar(title: const Text('Session Details')),
      body: SafeArea(
        child: state.when(
          data: (talk) => _TalkDetailBody(talk: talk),
          loading: () => const Center(
            key: ValueKey('talkDetailLoading'),
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => Center(
            key: const ValueKey('talkDetailError'),
            child: Text('Error: $error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _TalkDetailBody extends StatelessWidget {
  const _TalkDetailBody({required this.talk});

  final Talk talk;

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  void _askAiAboutTalk(BuildContext context) {
    final speakerNames = talk.speakers.map((s) => s.name).join(', ');
    final prompt = speakerNames.isEmpty
        ? 'Tell me about "${talk.title}".'
        : 'Tell me about "${talk.title}" by $speakerNames.';

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatTabRoot(initialPrompt: prompt)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // Hero Header Container
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withAlpha(20),
                colorScheme.surfaceContainerHighest.withAlpha(100),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                talk.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),
              // Information Ribbon
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Day pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 13,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          talk.day.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Track badge
                  TrackBadge(track: talk.track, fontSize: 12),
                  // Time & duration pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatTime(talk.startTime)} · ${talk.durationMinutes} min',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Speaker Profile Section
        if (talk.speakers.isNotEmpty) ...[
          Text(
            talk.speakers.length == 1 ? 'Speaker' : 'Speakers',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final speaker in talk.speakers) ...[
            _SpeakerCard(speaker: speaker, getInitials: _getInitials),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],

        // Abstract Card
        Text(
          'Abstract',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              talk.abstract,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // "Ask AI about this talk" Action Button
        FilledButton.icon(
          key: const ValueKey('askAiAboutTalkButton'),
          onPressed: () => _askAiAboutTalk(context),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: const Text(
            'Ask AI about this talk',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SpeakerCard extends StatelessWidget {
  const _SpeakerCard({required this.speaker, required this.getInitials});

  final Speaker speaker;
  final String Function(String) getInitials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initials = getInitials(speaker.name);

    final affiliation = [
      if (speaker.title.isNotEmpty) speaker.title,
      if (speaker.company != null && speaker.company!.isNotEmpty)
        speaker.company!,
    ].join(' · ');

    return Card(
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    speaker.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (affiliation.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      affiliation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
