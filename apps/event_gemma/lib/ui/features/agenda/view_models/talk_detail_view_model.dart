import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/talk.dart';
import '../../../providers/repository_providers.dart';

/// A single talk, keyed by [talkId], for the Agenda tab's detail screen
/// (and for citation-chip taps from the Chat tab navigating to the same
/// screen/id).
///
/// Riverpod 3.x's manual (non-codegen) `AsyncNotifierProvider...family`
/// factory is `NotifierT Function(ArgT arg)` (the family argument is passed
/// to the notifier's constructor, not to `build`) — so [talkId] is a
/// constructor field here, read from inside [build].
class TalkDetailViewModel extends AsyncNotifier<Talk> {
  TalkDetailViewModel(this.talkId);

  final String talkId;

  @override
  Future<Talk> build() {
    return ref.watch(agendaRepositoryProvider).getTalkById(talkId);
  }
}

/// `.family` because each talk detail screen/citation-chip target needs its
/// own instance keyed by talk id. `.autoDispose` for the same reason as
/// [agendaListViewModelProvider] — no shared-resource lifecycle concern.
final talkDetailViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<TalkDetailViewModel, Talk, String>(
      TalkDetailViewModel.new,
      // See `agendaListViewModelProvider`'s matching comment:
      // `TalkNotFoundException` is not transient, so Riverpod's default
      // retry-on-error is disabled here too.
      retry: (retryCount, error) => null,
    );
