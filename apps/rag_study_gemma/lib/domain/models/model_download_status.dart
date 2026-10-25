/// Phases of the dual-model (EmbeddingGemma 2 + Gemma 3 1B IT) setup flow.
enum ModelDownloadPhase {
  checking,
  notDownloaded,
  downloadingEmbedding,
  downloadingLlm,
  ready,
  failed,
}

/// Immutable status snapshot of the dual-model download pipeline.
class ModelDownloadStatus {
  const ModelDownloadStatus({
    required this.phase,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.currentModelName = '',
    this.errorMessage,
  });

  final ModelDownloadPhase phase;
  final int bytesReceived;
  final int totalBytes;
  final String currentModelName;
  final String? errorMessage;

  double get progress {
    if (phase == ModelDownloadPhase.ready) return 1.0;
    if (totalBytes <= 0) return 0.0;
    return (bytesReceived / totalBytes).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModelDownloadStatus &&
        other.phase == phase &&
        other.bytesReceived == bytesReceived &&
        other.totalBytes == totalBytes &&
        other.currentModelName == currentModelName &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(
    phase,
    bytesReceived,
    totalBytes,
    currentModelName,
    errorMessage,
  );
}
