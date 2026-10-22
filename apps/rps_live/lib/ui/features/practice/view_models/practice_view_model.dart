import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/classification_result.dart';
import '../../../providers/repository_providers.dart';

/// "Práctica libre" live confidence view: an animated meter/gauge per class
/// (paper/rock/scissors) updating in real time from
/// [classifierRepositoryProvider]'s `classificationStream`, outside any
/// countdown round.
///
/// Modeled as an [AsyncNotifier] (rather than plain [Notifier]) because the
/// underlying camera+classifier stream can fail (missing model asset, no
/// camera permission) — `AsyncValue` gives the view a built-in
/// loading/data/error tri-state without hand-rolled flags.
///
/// [build] bridges the push-based `classificationStream` into `AsyncValue`:
/// it awaits the *first* emission (or error) to resolve the initial
/// loading state, then every subsequent emission is pushed via
/// `state = AsyncData(...)` / `AsyncError(...)` directly, bypassing another
/// `build()` call (a `ref.watch`-driven rebuild would re-run
/// `initialize()`/re-subscribe on every single frame, which is wrong).
class PracticeViewModel extends AsyncNotifier<ClassificationResult?> {
  StreamSubscription<ClassificationResult>? _subscription;

  @override
  Future<ClassificationResult?> build() async {
    final classifierRepository = ref.watch(classifierRepositoryProvider);
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
      // Without this, leaving "Práctica libre" would never release the
      // camera/interpreter (see `VsAiViewModel.build()`'s matching
      // `onDispose`, and the addendum to
      // `doc/adr/0001-state-management-riverpod.md`), which would silently
      // defeat this provider's `.autoDispose` fix: the notifier itself
      // would be torn down on tab switch, but the shared
      // `ClassifierRepositoryImpl` it initialized would never be told to
      // release its resources.
      unawaited(classifierRepository.dispose());
    });

    await classifierRepository.initialize();

    final firstResult = Completer<ClassificationResult?>();
    _subscription = classifierRepository.classificationStream.listen(
      (result) {
        if (!firstResult.isCompleted) {
          firstResult.complete(result);
        } else {
          state = AsyncData(result);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!firstResult.isCompleted) {
          firstResult.completeError(error, stackTrace);
        } else {
          state = AsyncError(error, stackTrace);
        }
      },
    );
    return firstResult.future;
  }

  /// Toggles between front and rear cameras while keeping the practice stream
  /// active.
  Future<void> switchCamera() async {
    try {
      await ref.read(classifierRepositoryProvider).switchCamera();
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

// `.autoDispose`: see the addendum to
// `doc/adr/0001-state-management-riverpod.md` — ties this notifier's
// lifecycle to real widget unmount/remount on tab switch (releases the
// camera/interpreter when "Práctica libre" is left, re-initializes when
// revisited) instead of living for the whole app session.
final practiceViewModelProvider =
    AsyncNotifierProvider.autoDispose<PracticeViewModel, ClassificationResult?>(
      PracticeViewModel.new,
      // Riverpod 3.x retries a failed `build()` by default (exponential
      // backoff, up to ~10 attempts) before surfacing an `AsyncError`. That
      // default is wrong here: `ModelAssetNotFoundException` /
      // `CameraUnavailableException` are not transient — silently retrying
      // for up to a minute would just show a stuck loading spinner instead
      // of the explicit, immediate error state the ADR calls for. Disabled
      // so a failed `initialize()`/stream error surfaces immediately.
      retry: (retryCount, error) => null,
    );
