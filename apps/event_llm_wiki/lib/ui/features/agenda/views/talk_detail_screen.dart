import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/conference_day.dart';
import '../../../../domain/models/conference_track.dart';
import '../../../../domain/models/talk.dart';
import '../view_models/talk_detail_view_model.dart';

/// Full detail view of a single talk: title, speakers, abstract, day/track/
/// time. Reachable both from `AgendaListScreen` and from a `CitationChip`
/// tap in `ChatScreen`.
class TalkDetailScreen extends ConsumerWidget {
  const TalkDetailScreen({super.key, required this.talkId});

  final String talkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(talkDetailViewModelProvider(talkId));
    return Scaffold(
      appBar: AppBar(title: const Text('Talk details')),
      body: SafeArea(
        child: state.when(
          data: (talk) => _TalkDetail(talk: talk),
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

class _TalkDetail extends StatelessWidget {
  const _TalkDetail({required this.talk});

  final Talk talk;

  @override
  Widget build(BuildContext context) {
    final speakerNames = talk.speakers.map((s) => s.name).join(', ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(talk.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(speakerNames, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('${talk.day.label} · ${talk.track.label}'),
        Text(talk.startTime.toLocal().toString()),
        const SizedBox(height: 16),
        Text(talk.abstract),
      ],
    );
  }
}
