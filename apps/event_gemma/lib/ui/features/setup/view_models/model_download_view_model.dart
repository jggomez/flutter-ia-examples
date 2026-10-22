import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../../../providers/repository_providers.dart';

/// Drives the Chat tab's one-time model-download gate (see
/// `doc/adr/0005-model-download-flow.md`): [build] checks local status
/// first (so a relaunch with an already-downloaded model skips straight to
/// [ModelDownloadPhase.ready] with no network call), and [startDownload]
/// kicks off the actual streamed download when the user opts in from
/// `ModelSetupScreen`.
class ModelDownloadViewModel extends AsyncNotifier<ModelDownloadStatus> {
  @override
  Future<ModelDownloadStatus> build() {
    return ref.watch(modelDownloadRepositoryProvider).checkLocalStatus();
  }

  /// Checks whether the mobile device currently has an active Wi-Fi
  /// connection before presenting the download confirmation dialog.
  Future<bool> checkWifiConnected() {
    return ref.read(modelDownloadRepositoryProvider).isWifiConnected();
  }

  /// Starts (or restarts, if the previous attempt failed) the model
  /// download, pushing each `ModelDownloadRepository.download()` stream
  /// event into `state` as it arrives so `ModelSetupScreen` can render live
  /// progress.
  Future<void> startDownload({String? authToken}) async {
    final repository = ref.read(modelDownloadRepositoryProvider);
    await for (final status in repository.download(authToken: authToken)) {
      state = AsyncData(status);
    }
  }
}

/// `.autoDispose`: the download-gate screen is only ever visible before the
/// model is ready; once `ready`, `ChatTabRoot` swaps it out entirely, so
/// there's no reason to keep this notifier alive for the rest of the app
/// session. Unlike `chatViewModelProvider`, this provider owns no
/// long-lived native resource (the download itself is fire-and-forget
/// against `ModelDownloadRepositoryImpl`, which is stateless between calls
/// — see `doc/adr/0003-state-management-riverpod.md` for the contrast with
/// `chatViewModelProvider`'s deliberate non-`.autoDispose` exception).
final modelDownloadViewModelProvider =
    AsyncNotifierProvider.autoDispose<
      ModelDownloadViewModel,
      ModelDownloadStatus
    >(
      ModelDownloadViewModel.new,
      // See `agendaListViewModelProvider`'s matching comment: a failed
      // `checkLocalStatus()` (e.g. storage permission revoked) is not
      // transient, so Riverpod's default retry-on-error is disabled here
      // too.
      retry: (retryCount, error) => null,
    );
