import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/match_record.dart';
import '../../../providers/repository_providers.dart';

/// Persisted match history, read via [historyRepositoryProvider]. Survives
/// app restart because `HistoryRepository` is backed by Hive
/// (`doc/adr/0002-persistence-hive.md`).
///
/// Aggregate win/lose/tie stats are intentionally *not* stored on this
/// class — `HistoryScreen` derives them from [state]'s data via
/// `ComputeMatchStatsUseCase` (`domain/use_cases/compute_match_stats_use_case.dart`),
/// keeping that a reusable, independently-tested pure function rather than
/// duplicated view-model state.
class HistoryViewModel extends AsyncNotifier<List<MatchRecord>> {
  @override
  Future<List<MatchRecord>> build() {
    final historyRepository = ref.watch(historyRepositoryProvider);
    return historyRepository.getAll();
  }

  /// Re-runs [build] and awaits its result, e.g. for a pull-to-refresh
  /// gesture or after a new round is persisted elsewhere in the app.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

// `.autoDispose`: see the addendum to
// `doc/adr/0001-state-management-riverpod.md` — without this, the loaded
// `AsyncData<List<MatchRecord>>` was cached for the whole app session after
// the first visit to Historial, so a round played after that first visit
// never showed up. `.autoDispose` makes every (re)visit re-run `build()`
// (a fresh Hive read) instead.
final historyViewModelProvider =
    AsyncNotifierProvider.autoDispose<HistoryViewModel, List<MatchRecord>>(
      HistoryViewModel.new,
      // See the matching comment on `practiceViewModelProvider`: Riverpod's
      // default retry-on-error would silently retry a failed Hive read for
      // up to ~10 attempts instead of surfacing `HistoryPersistenceException`
      // immediately.
      retry: (retryCount, error) => null,
    );
