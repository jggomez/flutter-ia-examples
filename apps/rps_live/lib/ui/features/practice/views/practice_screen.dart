import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/classification_result.dart';
import '../../../../domain/models/move.dart';
import '../view_models/practice_view_model.dart';

/// "Práctica libre" screen: live per-class confidence meters, no countdown.
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(practiceViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Práctica libre')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: state.when(
            data: (result) => _ConfidenceMeters(result: result),
            loading: () => const Center(
              key: ValueKey('practiceLoading'),
              child: CircularProgressIndicator(),
            ),
            error: (error, stackTrace) => _PracticeError(error: error),
          ),
        ),
      ),
    );
  }
}

class _PracticeError extends StatelessWidget {
  const _PracticeError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        key: const ValueKey('practiceError'),
        _describe(error),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _describe(Object error) => error.toString();
}

class _ConfidenceMeters extends StatelessWidget {
  const _ConfidenceMeters({required this.result});

  final ClassificationResult? result;

  @override
  Widget build(BuildContext context) {
    final currentResult = result;
    if (currentResult == null) {
      return const Center(
        key: ValueKey('practiceNoResultYet'),
        child: Text('Esperando el primer cuadro de la cámara…'),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final move in Move.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _ConfidenceMeter(
              move: move,
              confidence: currentResult.confidenceFor(move),
              isTop: move == currentResult.topMove,
            ),
          ),
      ],
    );
  }
}

class _ConfidenceMeter extends StatelessWidget {
  const _ConfidenceMeter({
    required this.move,
    required this.confidence,
    required this.isTop,
  });

  final Move move;
  final double confidence;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _moveLabel(move),
              style: TextStyle(
                fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Text(
              key: ValueKey('confidenceValue_${move.name}'),
              '${(confidence * 100).round()}%',
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: ValueKey('confidenceMeter_${move.name}'),
            value: confidence.clamp(0.0, 1.0),
            minHeight: 12,
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
}
