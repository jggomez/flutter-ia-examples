import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/models/game_phase.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/repositories/classifier_repository.dart';
import 'package:rps_live/ui/features/vs_ai/view_models/vs_ai_view_model.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

/// Always returns 0 from [nextInt], so `VsAiViewModel`'s AI move is
/// deterministically `Move.values[0]` (paper) in every test below.
class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

const _paperResult = ClassificationResult(
  paperConfidence: 0.9,
  rockConfidence: 0.05,
  scissorsConfidence: 0.05,
);
const _rockResult = ClassificationResult(
  paperConfidence: 0.05,
  rockConfidence: 0.9,
  scissorsConfidence: 0.05,
);
const _scissorsResult = ClassificationResult(
  paperConfidence: 0.05,
  rockConfidence: 0.05,
  scissorsConfidence: 0.9,
);

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

ProviderContainer _makeContainer({
  required FakeClassifierRepository classifier,
  required FakeHistoryRepository history,
  Duration countdownTick = const Duration(milliseconds: 1),
}) {
  final container = ProviderContainer(
    overrides: [
      classifierRepositoryProvider.overrideWithValue(classifier),
      historyRepositoryProvider.overrideWithValue(history),
      vsAiViewModelProvider.overrideWith(
        () =>
            VsAiViewModel(countdownTick: countdownTick, random: _FixedRandom()),
      ),
    ],
  );
  addTearDown(container.dispose);
  // `vsAiViewModelProvider` is `.autoDispose` (see the addendum to
  // doc/adr/0001-state-management-riverpod.md): without an active listener,
  // Riverpod would tear it down (and rebuild it, resetting state) between
  // the `await`s these tests use. Holding a no-op listener for the
  // container's lifetime keeps it alive, the standard pattern for testing
  // `autoDispose` providers.
  container.listen(vsAiViewModelProvider, (_, _) {});
  return container;
}

void main() {
  group('VsAiViewModel', () {
    test('starts idle with a zeroed scoreboard', () async {
      final container = _makeContainer(
        classifier: FakeClassifierRepository(),
        history: FakeHistoryRepository(),
      );

      final state = container.read(vsAiViewModelProvider);

      expect(state.phase, GamePhase.idle);
      expect(state.stats.wins, 0);
      expect(state.stats.losses, 0);
      expect(state.stats.ties, 0);
    });

    test('initializes the classifier repository on build', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
      );

      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();

      expect(classifier.initializeCallCount, 1);
    });

    test('startRound runs the countdown then reveals the AI move (random) and '
        'the player move (latest classification.topMove)', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      classifier.emit(_rockResult); // player shows rock

      await container.read(vsAiViewModelProvider.notifier).startRound();

      final state = container.read(vsAiViewModelProvider);
      expect(state.phase, GamePhase.result);
      expect(state.aiMove, Move.paper); // _FixedRandom -> Move.values[0]
      expect(state.playerMove, Move.rock);
      expect(state.outcome, RoundOutcome.lose); // paper beats rock
      expect(state.stats.losses, 1);
    });

    test('countdown value counts down from 3 to 1 before revealing', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
        countdownTick: const Duration(milliseconds: 20),
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      classifier.emit(_paperResult);

      final seenCountdownValues = <int>[];
      container.listen(vsAiViewModelProvider, (previous, next) {
        if (next.phase == GamePhase.countdown) {
          seenCountdownValues.add(next.countdownValue);
        }
      }, fireImmediately: true);

      await container.read(vsAiViewModelProvider.notifier).startRound();

      expect(seenCountdownValues, [3, 2, 1]);
    });

    test('accumulates wins/losses/ties across multiple rounds', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      final notifier = container.read(vsAiViewModelProvider.notifier);

      classifier.emit(_paperResult); // paper vs ai-paper -> tie
      await notifier.startRound();
      classifier.emit(_scissorsResult); // scissors vs ai-paper -> win
      await notifier.startRound();
      classifier.emit(_rockResult); // rock vs ai-paper -> lose
      await notifier.startRound();

      final state = container.read(vsAiViewModelProvider);
      expect(state.stats.ties, 1);
      expect(state.stats.wins, 1);
      expect(state.stats.losses, 1);
    });

    test('ignores startRound while a round is already in progress', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
        countdownTick: const Duration(milliseconds: 30),
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      classifier.emit(_paperResult);
      final notifier = container.read(vsAiViewModelProvider.notifier);

      final first = notifier.startRound();
      final second = notifier.startRound(); // should be a no-op
      await Future.wait([first, second]);

      // A single round completed (one result), not a restarted/second one.
      expect(container.read(vsAiViewModelProvider).phase, GamePhase.result);
    });

    test('reverts to idle with an error message when no player move has been '
        'classified yet by reveal time', () async {
      final classifier = FakeClassifierRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: FakeHistoryRepository(),
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      // No `classifier.emit(...)` call: no classification available.

      await container.read(vsAiViewModelProvider.notifier).startRound();

      final state = container.read(vsAiViewModelProvider);
      expect(state.phase, GamePhase.idle);
      expect(state.errorMessage, isNotNull);
      expect(state.playerMove, isNull);
    });

    test(
      'surfaces a camera/model initialization failure as errorMessage',
      () async {
        final classifier = FakeClassifierRepository()
          ..initializeError = const CameraUnavailableException(
            'Camera permission denied.',
          );
        final container = _makeContainer(
          classifier: classifier,
          history: FakeHistoryRepository(),
        );

        container.read(vsAiViewModelProvider);
        await _flushMicrotasks();

        expect(
          container.read(vsAiViewModelProvider).errorMessage,
          'Camera permission denied.',
        );
      },
    );

    test('persists a completed round to HistoryRepository', () async {
      final classifier = FakeClassifierRepository();
      final history = FakeHistoryRepository();
      final container = _makeContainer(
        classifier: classifier,
        history: history,
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      classifier.emit(_rockResult);

      await container.read(vsAiViewModelProvider.notifier).startRound();
      await _flushMicrotasks();

      final persisted = await history.getAll();
      expect(persisted, hasLength(1));
      expect(persisted.single.playerMove, Move.rock);
      expect(persisted.single.aiMove, Move.paper);
      expect(persisted.single.outcome, RoundOutcome.lose);
    });

    test('surfaces a non-fatal errorMessage when persistence fails, without '
        'losing the already-computed round result', () async {
      final classifier = FakeClassifierRepository();
      final history = FakeHistoryRepository()
        ..addError = Exception('disk full');
      final container = _makeContainer(
        classifier: classifier,
        history: history,
      );
      container.read(vsAiViewModelProvider);
      await _flushMicrotasks();
      classifier.emit(_paperResult);

      await container.read(vsAiViewModelProvider.notifier).startRound();
      await _flushMicrotasks();

      final state = container.read(vsAiViewModelProvider);
      expect(state.phase, GamePhase.result);
      expect(state.outcome, RoundOutcome.tie);
      expect(state.errorMessage, contains('disk full'));
    });

    test(
      'disposes the classifier repository when the provider is disposed',
      () async {
        final classifier = FakeClassifierRepository();
        final container = _makeContainer(
          classifier: classifier,
          history: FakeHistoryRepository(),
        );
        container.read(vsAiViewModelProvider);
        await _flushMicrotasks();

        container.dispose();

        expect(classifier.disposeCallCount, 1);
      },
    );
  });
}
