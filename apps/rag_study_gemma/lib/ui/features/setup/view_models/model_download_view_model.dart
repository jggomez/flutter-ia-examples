import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../../../providers/repository_providers.dart';

/// Manages the dual-model setup flow for EmbeddingGemma 2 (270M) and
/// Gemma 3 1B IT (see ADR 0004 & ADR 0005).
class ModelDownloadViewModel extends AsyncNotifier<ModelDownloadStatus> {
  @override
  Future<ModelDownloadStatus> build() async {
    final ready = await ref
        .watch(modelDownloadRepositoryProvider)
        .areModelsReady();
    return ModelDownloadStatus(
      phase: ready
          ? ModelDownloadPhase.ready
          : ModelDownloadPhase.notDownloaded,
    );
  }

  /// Checks whether the device has an active Wi-Fi connection.
  Future<bool> checkWifi() {
    return ref.read(modelDownloadRepositoryProvider).isUnmeteredWifi();
  }

  /// Starts or retries the sequential two-stage model download.
  Future<void> startDownload({String? hfToken}) async {
    final repository = ref.read(modelDownloadRepositoryProvider);
    final sanitizedToken = hfToken?.trim();
    try {
      await for (final status in repository.downloadModels(
        hfToken: (sanitizedToken == null || sanitizedToken.isEmpty)
            ? null
            : sanitizedToken,
      )) {
        state = AsyncData(status);
      }
    } catch (error) {
      state = AsyncData(
        ModelDownloadStatus(
          phase: ModelDownloadPhase.failed,
          errorMessage: '$error',
        ),
      );
    }
  }

  /// Deletes downloaded model artifacts from disk and resets state.
  Future<void> deleteModels() async {
    await ref.read(modelDownloadRepositoryProvider).deleteModels();
    state = const AsyncData(
      ModelDownloadStatus(phase: ModelDownloadPhase.notDownloaded),
    );
  }
}

/// Auto-disposing provider for the setup gate.
final modelDownloadViewModelProvider =
    AsyncNotifierProvider.autoDispose<
      ModelDownloadViewModel,
      ModelDownloadStatus
    >(ModelDownloadViewModel.new, retry: (retryCount, error) => null);
