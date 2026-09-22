import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/talk.dart';
import '../../../providers/repository_providers.dart';

/// All bundled talks, chronologically ordered, for the Agenda tab's list
/// view.
///
/// `AsyncNotifier` (not plain `Notifier`) because reading
/// `assets/agenda.json` is async and can, in principle, fail
/// (`AgendaLoadException`) — `AsyncValue` gives the screen a built-in
/// loading/data/error tri-state, matching the convention in
/// `apps/rps_live`'s view models.
class AgendaListViewModel extends AsyncNotifier<List<Talk>> {
  @override
  Future<List<Talk>> build() async {
    final talks = await ref.watch(agendaRepositoryProvider).getAllTalks();
    return [...talks]..sort((a, b) => a.startTime.compareTo(b.startTime));
  }
}

/// `.autoDispose`: the Agenda tab's list is cheap to reload and has no
/// shared-resource lifecycle concern (unlike `chatViewModelProvider` — see
/// `doc/adr/0003-state-management-riverpod.md`), so it follows
/// `apps/rps_live`'s default pattern of tying provider lifecycle to real
/// widget unmount/remount.
final agendaListViewModelProvider =
    AsyncNotifierProvider.autoDispose<AgendaListViewModel, List<Talk>>(
      AgendaListViewModel.new,
      // Riverpod 3.x retries a failed `build()` by default (exponential
      // backoff, up to ~10 attempts) before surfacing an `AsyncError` — see
      // `apps/rps_live`'s `practiceViewModelProvider` for the identical
      // convention this mirrors. `AgendaLoadException` (a malformed/missing
      // bundled asset) is not transient, so retrying would just show a
      // stuck loading spinner instead of the explicit error state
      // `AgendaListScreen` should render immediately.
      retry: (retryCount, error) => null,
    );
