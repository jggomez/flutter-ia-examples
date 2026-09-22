import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/game_phase.dart';
import '../../../../domain/models/move.dart';
import '../../../../domain/models/round_outcome.dart';
import '../view_models/vs_ai_view_model.dart';

/// "Tú vs. IA" screen: 3-2-1 countdown, simultaneous reveal, animated
/// win/lose/tie result, running session scoreboard.
///
/// Kept "dumb": all state transitions live in [VsAiViewModel]; this widget
/// only renders [VsAiState] and forwards the "start round" button tap.
class VsAiScreen extends ConsumerWidget {
  const VsAiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vsAiViewModelProvider);
    final notifier = ref.read(vsAiViewModelProvider.notifier);
    final canStartRound =
        state.phase == GamePhase.idle || state.phase == GamePhase.result;

    return Scaffold(
      appBar: AppBar(title: const Text('Tú vs. IA')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _Scoreboard(state: state),
              const SizedBox(height: 12),
              if (state.errorMessage case final message?) ...[
                _ErrorBanner(message: message),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: Center(child: _PhaseContent(state: state)),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('startRoundButton'),
                  onPressed: canStartRound ? notifier.startRound : null,
                  child: Text(
                    state.phase == GamePhase.result
                        ? 'Jugar de nuevo'
                        : 'Empezar ronda',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.state});

  final VsAiState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ScoreboardEntry(label: 'Ganadas', value: state.stats.wins),
        _ScoreboardEntry(label: 'Perdidas', value: state.stats.losses),
        _ScoreboardEntry(label: 'Empates', value: state.stats.ties),
      ],
    );
  }
}

class _ScoreboardEntry extends StatelessWidget {
  const _ScoreboardEntry({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', style: Theme.of(context).textTheme.headlineMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('vsAiErrorBanner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _PhaseContent extends StatelessWidget {
  const _PhaseContent({required this.state});

  final VsAiState state;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case GamePhase.idle:
        return const Text(
          'Apunta la cámara a tu mano y presiona "Empezar ronda".',
          textAlign: TextAlign.center,
        );
      case GamePhase.countdown:
        return Text(
          '${state.countdownValue}',
          key: const ValueKey('countdownValue'),
          style: Theme.of(context).textTheme.displayLarge,
        );
      case GamePhase.revealing:
      case GamePhase.result:
        return _RevealAndResult(state: state);
    }
  }
}

class _RevealAndResult extends StatelessWidget {
  const _RevealAndResult({required this.state});

  final VsAiState state;

  @override
  Widget build(BuildContext context) {
    final playerMove = state.playerMove;
    final aiMove = state.aiMove;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MoveDisplay(label: 'Tú', move: playerMove),
            const Text('VS'),
            _MoveDisplay(label: 'IA', move: aiMove),
          ],
        ),
        const SizedBox(height: 16),
        if (state.outcome case final outcome?)
          Text(
            key: const ValueKey('roundOutcome'),
            _outcomeLabel(outcome),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
      ],
    );
  }

  String _outcomeLabel(RoundOutcome outcome) => switch (outcome) {
    RoundOutcome.win => '¡Ganaste!',
    RoundOutcome.lose => 'Perdiste',
    RoundOutcome.tie => 'Empate',
  };
}

class _MoveDisplay extends StatelessWidget {
  const _MoveDisplay({required this.label, required this.move});

  final String label;
  final Move? move;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          move == null ? '?' : _moveLabel(move!),
          style: Theme.of(context).textTheme.headlineMedium,
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
