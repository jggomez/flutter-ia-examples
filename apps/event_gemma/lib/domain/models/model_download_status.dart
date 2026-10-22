/// Lifecycle phase of the on-device model download (see
/// `doc/adr/0005-model-download-flow.md`).
///
/// This phase is never itself persisted (no Hive flag) — file existence on
/// disk, checked by `ModelDownloadRepository.checkLocalStatus()`, is always
/// the source of truth. A `ModelDownloadStatus` is a point-in-time snapshot
/// derived from that check or from an in-flight `download()` stream.
enum ModelDownloadPhase {
  /// No local model file (or only a stale/incomplete `.part` file — same
  /// treatment, see the ADR's "not resumable" decision).
  notDownloaded,

  /// A `download()` stream is actively writing to the `.part` file.
  downloading,

  /// A validated (min-size sanity-checked, atomically renamed) model file is
  /// present at `AppStorageService`'s model path.
  ready,

  /// The most recent `download()` attempt failed (network error, storage
  /// error, or `ValidateDownloadedModelUseCase` rejected the file).
  failed,
}

/// A snapshot of model-download progress/outcome, emitted by
/// `ModelDownloadRepository.download()` and by
/// `ModelDownloadRepository.checkLocalStatus()`.
class ModelDownloadStatus {
  const ModelDownloadStatus({
    required this.phase,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.errorMessage,
  });

  final ModelDownloadPhase phase;

  /// Bytes written to the `.part` file so far. Meaningful only while
  /// [phase] is [ModelDownloadPhase.downloading].
  final int bytesDownloaded;

  /// Expected total size in bytes, from the response's `Content-Length`, if
  /// the server provided one. Null means indeterminate progress.
  final int? totalBytes;

  /// Set only when [phase] is [ModelDownloadPhase.failed].
  final String? errorMessage;

  /// `bytesDownloaded / totalBytes` in `[0.0, 1.0]`, or null when
  /// [totalBytes] is unknown (caller should render an indeterminate
  /// progress indicator in that case).
  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesDownloaded / total).clamp(0.0, 1.0);
  }
}
