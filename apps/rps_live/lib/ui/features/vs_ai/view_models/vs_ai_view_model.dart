import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_exception.dart';
import '../../../../domain/models/classification_result.dart';
import '../../../../domain/models/game_phase.dart';
import '../../../../domain/models/match_record.dart';
import '../../../../domain/models/match_stats.dart';
import '../../../../domain/models/move.dart';
import '../../../../domain/models/round_outcome.dart';
import '../../../../domain/repositories/classifier_repository.dart';
import '../../../../domain/repositories/history_repository.dart';
import '../../../../domain/use_cases/determine_round_result_use_case.dart';
import '../../../providers/repository_providers.dart';

/// Immutable UI state for the "Tú vs. IA" screen.
class VsAiState {
  const VsAiState({
    this.phase = GamePhase.idle,
    this.countdownValue = 0,
    this.playerMove,
    this.aiMove,
    this.outcome,
    this.stats = const MatchStats.zero(),
    this.liveClassification,
    this.errorMessage,
  });

  final GamePhase phase;

  /// The current countdown number shown during [GamePhase.countdown]
  /// (e.g. 3, 2, 1); meaningless in other phases.
  final int countdownValue;

  /// Only non-null from [GamePhase.revealing] onward.
  final Move? playerMove;

  /// Only non-null from [GamePhase.revealing] onward. Chosen randomly when
  /// the round *starts* (see [VsAiViewModel.startRound] doc comment), not
  /// at reveal time.
  final Move? aiMove;

  /// Only non-null during/after [GamePhase.result].
  final RoundOutcome? outcome;

  /// Running session scoreboard, updated after each completed round. Not
  /// persisted directly — see `HistoryRepository` for cross-restart history.
  final MatchStats stats;

  /// Latest real-time classification + preview frame from the camera stream.
  final ClassificationResult? liveClassification;

  /// Set when the classifier/camera pipeline fails to initialize or errors
  /// mid-stream, or when a completed round fails to persist. Non-fatal: the
  /// state machine keeps working (e.g. a persistence failure still shows
  /// the round's result), this is surfaced so the UI can show a banner.
  final String? errorMessage;

  VsAiState copyWith({
    GamePhase? phase,
    int? countdownValue,
    Move? playerMove,
    Move? aiMove,
    RoundOutcome? outcome,
    MatchStats? stats,
    ClassificationResult? liveClassification,
    String? errorMessage,
    bool clearRoundResult = false,
    bool clearError = false,
  }) {
    return VsAiState(
      phase: phase ?? this.phase,
      countdownValue: countdownValue ?? this.countdownValue,
      playerMove: clearRoundResult ? null : (playerMove ?? this.playerMove),
      aiMove: clearRoundResult ? null : (aiMove ?? this.aiMove),
      outcome: clearRoundResult ? null : (outcome ?? this.outcome),
      stats: stats ?? this.stats,
      liveClassification: liveClassification ?? this.liveClassification,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives the "Tú vs. IA" countdown/reveal/result state machine.
///
/// Consumes [classifierRepositoryProvider] for the live move classification
/// and [historyRepositoryProvider] to persist completed rounds, plus
/// [DetermineRoundResultUseCase] for the win/lose/tie rule — never talks to
/// `package:camera`/`package:flutter_litert`/`package:hive` directly, which
/// is what makes this notifier testable with
/// `ProviderContainer(overrides: [...])` and fake repositories.
///
/// ## AI-move-timing decision
///
/// The AI's move is chosen **uniformly at random the instant [startRound]
/// begins the countdown** — not sampled from anything, and not decided at
/// reveal time. Two reasons:
///
/// 1. **Fairness/anti-cheat**: the AI's move is locked in *before* the
///    player's hand gesture is visible to (or classified by) the camera at
///    all, so there is no way for the "AI" to react to the player's choice,
///    mirroring how a physical opponent would need to commit before seeing
///    your hand.
/// 2. **Decoupling from classifier timing**: the classifier stream is
///    sampled *once*, at the moment the countdown reaches zero, purely to
///    read the player's move (`_latestClassification?.topMove`) — the ADR
///    (`doc/adr/0001-state-management-riverpod.md`) already establishes
///    this "sample only at reveal time" rule for the *player's* move. The
///    AI move deliberately does not follow that rule at all, since it has
///    no dependency on the camera pipeline.
class VsAiViewModel extends Notifier<VsAiState> {
  // Not `this._countdownTick`/`this._countdownStart`/
  // `this._determineRoundResultUseCase`: a leading underscore in a
  // named-parameter name makes it library-private, which would break
  // tests (a different library) overriding these via
  // `vsAiViewModelProvider.overrideWith(() => VsAiViewModel(countdownTick:
  // ..., random: ...))`.
  VsAiViewModel({
    Duration countdownTick = const Duration(seconds: 1),
    int countdownStart = 3,
    Random? random,
    DetermineRoundResultUseCase determineRoundResultUseCase =
        const DetermineRoundResultUseCase(),
  }) : _countdownTick = countdownTick, // ignore: prefer_initializing_formals
       _countdownStart = countdownStart, // ignore: prefer_initializing_formals
       _random = random ?? Random(),
       // ignore: prefer_initializing_formals
       _determineRoundResultUseCase = determineRoundResultUseCase;

  final Duration _countdownTick;
  final int _countdownStart;
  final Random _random;
  final DetermineRoundResultUseCase _determineRoundResultUseCase;

  StreamSubscription<ClassificationResult>? _classificationSubscription;
  ClassificationResult? _latestClassification;
  bool _disposed = false;

  @override
  VsAiState build() {
    final classifierRepository = ref.watch(classifierRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_classificationSubscription?.cancel());
      unawaited(classifierRepository.dispose());
    });

    unawaited(_initializeClassifier(classifierRepository));
    return const VsAiState();
  }

  Future<void> _initializeClassifier(
    ClassifierRepository classifierRepository,
  ) async {
    try {
      await classifierRepository.initialize();
      if (_disposed) return;
      _classificationSubscription = classifierRepository.classificationStream
          .listen(
            (result) {
              _latestClassification = result;
              if (!_disposed && state.phase != GamePhase.countdown) {
                state = state.copyWith(liveClassification: result);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!_disposed) {
                state = state.copyWith(errorMessage: _describe(error));
              }
            },
          );
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(errorMessage: _describe(error));
      }
    }
  }

  /// Toggles between the front and rear cameras without interrupting the
  /// active round or classifier stream.
  Future<void> switchCamera() async {
    try {
      await ref.read(classifierRepositoryProvider).switchCamera();
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(errorMessage: _describe(error));
      }
    }
  }

  /// Starts a new round: picks the AI's move, runs the 3-2-1 countdown,
  /// reveals both moves, computes the outcome, updates the scoreboard and
  /// persists the round to history. A no-op while a round is already in
  /// progress ([GamePhase.countdown]/[GamePhase.revealing]).
  Future<void> startRound() async {
    if (state.phase == GamePhase.countdown ||
        state.phase == GamePhase.revealing) {
      return;
    }

    final aiMove = Move.values[_random.nextInt(Move.values.length)];

    var isFirstTick = true;
    for (var tick = _countdownStart; tick >= 1; tick--) {
      // Clearing the previous round's result/error happens on the very
      // first tick only, folded into the same state update that enters
      // GamePhase.countdown, so exactly one state transition is emitted
      // per countdown tick (no separate "phase changed but countdownValue
      // is stale" transient state).
      state = state.copyWith(
        phase: GamePhase.countdown,
        countdownValue: tick,
        liveClassification: _latestClassification,
        clearRoundResult: isFirstTick,
        clearError: isFirstTick,
      );
      isFirstTick = false;
      await Future<void>.delayed(_countdownTick);
      if (_disposed) return;
    }

    final playerMove = _latestClassification?.topMove;
    if (playerMove == null) {
      state = state.copyWith(
        phase: GamePhase.idle,
        errorMessage:
            'No player move detected yet — point the camera at your hand '
            'and try again.',
      );
      return;
    }

    state = state.copyWith(
      phase: GamePhase.revealing,
      playerMove: playerMove,
      aiMove: aiMove,
      liveClassification: _latestClassification,
    );

    final outcome = _determineRoundResultUseCase(
      playerMove: playerMove,
      aiMove: aiMove,
    );
    final updatedStats = MatchStats(
      wins: state.stats.wins + (outcome == RoundOutcome.win ? 1 : 0),
      losses: state.stats.losses + (outcome == RoundOutcome.lose ? 1 : 0),
      ties: state.stats.ties + (outcome == RoundOutcome.tie ? 1 : 0),
    );

    state = state.copyWith(
      phase: GamePhase.result,
      outcome: outcome,
      stats: updatedStats,
    );

    await _persistRound(
      playerMove: playerMove,
      aiMove: aiMove,
      outcome: outcome,
    );
  }

  Future<void> _persistRound({
    required Move playerMove,
    required Move aiMove,
    required RoundOutcome outcome,
  }) async {
    final HistoryRepository historyRepository = ref.read(
      historyRepositoryProvider,
    );
    try {
      await historyRepository.add(
        MatchRecord(
          id: _generateRoundId(),
          playedAt: DateTime.now(),
          playerMove: playerMove,
          aiMove: aiMove,
          outcome: outcome,
        ),
      );
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Round result was not saved: ${_describe(error)}',
        );
      }
    }
  }

  String _generateRoundId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  String _describe(Object error) =>
      error is AppException ? error.message : error.toString();
}

// `.autoDispose`: see the addendum to
// `doc/adr/0001-state-management-riverpod.md` — this ties the notifier's
// lifecycle to `app.dart`'s real widget unmount/remount on tab switch
// (`ref.onDispose` releases the camera/interpreter when the tab is left,
// `build()` re-runs and re-initializes when it's revisited), instead of the
// notifier living for the whole app session regardless of whether "Tú vs.
// IA" is on screen.
final vsAiViewModelProvider =
    NotifierProvider.autoDispose<VsAiViewModel, VsAiState>(VsAiViewModel.new);
