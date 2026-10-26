/// Lifecycle phase for the on-device `gemma-4-E2B-it.litertlm` (2.58 GB) artifact.
enum ModelDownloadPhase {
  checking,
  notDownloaded,
  wifiRequired,
  downloading,
  ready,
  error,
}

/// Immutable state snapshot for model readiness and streaming download progress.
class ModelDownloadState {
  const ModelDownloadState({
    this.phase = ModelDownloadPhase.checking,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.progress = 0.0,
    this.isOnWifi = true,
    this.errorMessage,
    this.modelFilePath,
  });

  final ModelDownloadPhase phase;
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final bool isOnWifi;
  final String? errorMessage;
  final String? modelFilePath;

  bool get isReady => phase == ModelDownloadPhase.ready;
  bool get isDownloading => phase == ModelDownloadPhase.downloading;
  bool get hasError => phase == ModelDownloadPhase.error;

  double get downloadedMb => downloadedBytes / (1024 * 1024);
  double get totalMb => totalBytes / (1024 * 1024);
  double get downloadedGb => downloadedBytes / (1024 * 1024 * 1024);
  double get totalGb => totalBytes / (1024 * 1024 * 1024);

  ModelDownloadState copyWith({
    ModelDownloadPhase? phase,
    int? downloadedBytes,
    int? totalBytes,
    double? progress,
    bool? isOnWifi,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? modelFilePath,
  }) {
    return ModelDownloadState(
      phase: phase ?? this.phase,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      progress: progress ?? this.progress,
      isOnWifi: isOnWifi ?? this.isOnWifi,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      modelFilePath: modelFilePath ?? this.modelFilePath,
    );
  }
}
