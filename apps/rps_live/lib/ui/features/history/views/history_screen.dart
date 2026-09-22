import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/match_record.dart';
import '../../../../domain/models/match_stats.dart';
import '../../../../domain/models/move.dart';
import '../../../../domain/models/round_outcome.dart';
import '../../../../domain/use_cases/compute_match_stats_use_case.dart';
import '../view_models/history_view_model.dart';

/// Match history screen: list of past rounds + aggregate stats.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static const _computeMatchStats = ComputeMatchStatsUseCase();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: SafeArea(
        child: state.when(
          data: (records) => _HistoryList(
            records: records,
            stats: _computeMatchStats(records),
          ),
          loading: () => const Center(
            key: ValueKey('historyLoading'),
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => Center(
            child: Text(
              key: const ValueKey('historyError'),
              'Error: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.records, required this.stats});

  final List<MatchRecord> records;
  final MatchStats stats;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(
        key: ValueKey('historyEmpty'),
        child: Text('Aún no has jugado ninguna ronda.'),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            key: const ValueKey('historyStatsSummary'),
            '${stats.wins}V - ${stats.losses}D - ${stats.ties}E '
            '(${records.length} rondas)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return ListTile(
                key: ValueKey('historyItem_${record.id}'),
                leading: _OutcomeIcon(outcome: record.outcome),
                title: Text(
                  '${_moveLabel(record.playerMove)} vs '
                  '${_moveLabel(record.aiMove)}',
                ),
                subtitle: Text(record.playedAt.toLocal().toString()),
                trailing: Text(_outcomeLabel(record.outcome)),
              );
            },
          ),
        ),
      ],
    );
  }

  String _moveLabel(Move move) => switch (move) {
    Move.paper => 'Papel',
    Move.rock => 'Piedra',
    Move.scissors => 'Tijera',
  };

  String _outcomeLabel(RoundOutcome outcome) => switch (outcome) {
    RoundOutcome.win => 'Ganada',
    RoundOutcome.lose => 'Perdida',
    RoundOutcome.tie => 'Empate',
  };
}

class _OutcomeIcon extends StatelessWidget {
  const _OutcomeIcon({required this.outcome});

  final RoundOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return switch (outcome) {
      RoundOutcome.win => const Icon(Icons.check_circle, color: Colors.green),
      RoundOutcome.lose => const Icon(Icons.cancel, color: Colors.red),
      RoundOutcome.tie => const Icon(Icons.remove_circle, color: Colors.grey),
    };
  }
}
