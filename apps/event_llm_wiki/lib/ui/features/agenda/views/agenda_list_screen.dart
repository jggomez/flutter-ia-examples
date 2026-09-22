import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/conference_day.dart';
import '../../../../domain/models/conference_track.dart';
import '../../../../domain/models/talk.dart';
import '../view_models/agenda_list_view_model.dart';
import 'talk_detail_screen.dart';

/// Browsable "wiki" list of every talk in the bundled agenda, grouped by
/// day/track. Tapping a talk pushes `TalkDetailScreen` for its id.
class AgendaListScreen extends ConsumerWidget {
  const AgendaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agendaListViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      body: SafeArea(
        child: state.when(
          data: (talks) => _AgendaList(talks: talks),
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

class _AgendaList extends StatelessWidget {
  const _AgendaList({required this.talks});

  final List<Talk> talks;

  @override
  Widget build(BuildContext context) {
    if (talks.isEmpty) {
      return const Center(
        key: ValueKey('agendaEmpty'),
        child: Text('No talks in this agenda yet.'),
      );
    }

    final groups = <(ConferenceDay, ConferenceTrack), List<Talk>>{};
    for (final talk in talks) {
      groups.putIfAbsent((talk.day, talk.track), () => []).add(talk);
    }
    final groupKeys = groups.keys.toList()
      ..sort((a, b) {
        final byDay = a.$1.index.compareTo(b.$1.index);
        if (byDay != 0) return byDay;
        return a.$2.index.compareTo(b.$2.index);
      });

    return ListView(
      children: [
        for (final key in groupKeys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '${key.$1.label} · ${key.$2.label}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final talk in groups[key]!)
            ListTile(
              key: ValueKey('talkListItem_${talk.id}'),
              title: Text(talk.title),
              subtitle: Text(talk.startTime.toLocal().toString()),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TalkDetailScreen(talkId: talk.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
