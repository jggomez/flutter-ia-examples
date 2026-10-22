import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/conference_day.dart';
import '../../../../domain/models/talk.dart';
import '../../../core/widgets/track_badge.dart';
import '../view_models/agenda_list_view_model.dart';
import 'talk_detail_screen.dart';

/// Browsable "wiki" list of every talk in the bundled agenda, with interactive
/// Day filtering chips, categorical track badges, and rich talk cards.
class AgendaListScreen extends ConsumerWidget {
  const AgendaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agendaListViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: SafeArea(
        child: state.when(
          data: (talks) => _AgendaBody(allTalks: talks),
          loading: () => const Center(
            key: ValueKey('agendaLoading'),
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => Center(
            key: const ValueKey('agendaError'),
            child: Text('Error: $error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _AgendaBody extends StatefulWidget {
  const _AgendaBody({required this.allTalks});

  final List<Talk> allTalks;

  @override
  State<_AgendaBody> createState() => _AgendaBodyState();
}

class _AgendaBodyState extends State<_AgendaBody> {
  ConferenceDay? _selectedDay;

  String _formatDayChipLabel(ConferenceDay day) {
    final dayTalks = widget.allTalks.where((t) => t.day == day).toList();
    if (dayTalks.isEmpty) return day.label;
    final date = dayTalks.first.startTime;
    final month = switch (date.month) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      _ => 'Dec',
    };
    return '${day.label} · $month ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allTalks.isEmpty) {
      return const Center(
        key: ValueKey('agendaEmpty'),
        child: Text('No talks in this agenda yet.'),
      );
    }

    final filteredTalks = _selectedDay == null
        ? widget.allTalks
        : widget.allTalks.where((t) => t.day == _selectedDay).toList();

    return Column(
      children: [
        // Horizontal Day filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Days'),
                  selected: _selectedDay == null,
                  onSelected: (_) => setState(() => _selectedDay = null),
                ),
                const SizedBox(width: 8),
                for (final day in ConferenceDay.values) ...[
                  FilterChip(
                    label: Text(_formatDayChipLabel(day)),
                    selected: _selectedDay == day,
                    onSelected: (selected) {
                      setState(() {
                        _selectedDay = selected ? day : null;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Filtered Talk List
        Expanded(
          child: filteredTalks.isEmpty
              ? const Center(child: Text('No talks scheduled for this day.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: filteredTalks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final talk = filteredTalks[index];
                    return _RichTalkCard(
                      key: ValueKey('talkListItem_${talk.id}'),
                      talk: talk,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TalkDetailScreen(talkId: talk.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RichTalkCard extends StatelessWidget {
  const _RichTalkCard({super.key, required this.talk, required this.onTap});

  final Talk talk;
  final VoidCallback onTap;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final primarySpeaker = talk.speakers.isNotEmpty
        ? talk.speakers.first
        : null;
    final speakerInitials = primarySpeaker != null
        ? _getInitials(primarySpeaker.name)
        : 'AI';
    final speakerSummary = talk.speakers
        .map((s) {
          if (s.company != null && s.company!.isNotEmpty) {
            return '${s.name} (${s.company})';
          }
          return s.name;
        })
        .join(', ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time and track row
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatTime(talk.startTime)} · ${talk.durationMinutes}m',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TrackBadge(track: talk.track),
                ],
              ),
              const SizedBox(height: 10),
              // Talk title
              Text(
                talk.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              // Speaker row
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      speakerInitials,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      speakerSummary.isEmpty
                          ? 'Conference Session'
                          : speakerSummary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
