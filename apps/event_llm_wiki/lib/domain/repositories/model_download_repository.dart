import '../../core/error/app_exception.dart';
import '../models/model_download_status.dart';

/// Abstraction over acquiring the on-device `.litertlm` model file (see
/// `doc/adr/0005-model-download-flow.md`).
///
/// File existence at `AppStorageService`'s model path is always the source
/// of truth for whether the model is ready — there is no separate
/// "downloaded" flag persisted anywhere (not in Hive, not in
/// `shared_preferences`). This keeps a force-quit-mid-download-then-relaunch
/// trivially correct: [checkLocalStatus] just re-stats the file/`.part`
/// file, no stale flag to reconcile.
abstract class ModelDownloadRepository {
  /// Stats local storage (via `AppStorageService`) to determine the current
  /// [ModelDownloadStatus] without starting a download:
  /// - a validated model file present -> [ModelDownloadPhase.ready]
  /// - no file, or only a leftover `.part` file ->
  ///   [ModelDownloadPhase.notDownloaded] (a leftover `.part` is discarded
  ///   here, not resumed — see the ADR)
  ///
  /// Throws [ModelDownloadException] if the filesystem check itself fails
  /// (e.g. storage permission revoked).
  Future<ModelDownloadStatus> checkLocalStatus();

  /// Streams the model to a `.part` file, then runs
  /// `ValidateDownloadedModelUseCase` and atomically renames it into place
  /// on success. Emits a [ModelDownloadStatus] per progress update
  /// ([ModelDownloadPhase.downloading] with growing [ModelDownloadStatus.bytesDownloaded]),
  /// ending with either one final [ModelDownloadPhase.ready] event or a
  /// [ModelDownloadPhase.failed] event — this stream does not throw, so
  /// consumers can render [ModelDownloadStatus.errorMessage] rather than
  /// needing a separate `catchError` path.
  ///
  /// Not resumable: any pre-existing `.part` file is deleted before a fresh
  /// download starts (see the ADR for why Range-header resume was
  /// rejected).
  Stream<ModelDownloadStatus> download();
}

/// Thrown by [ModelDownloadRepository.checkLocalStatus] when the local
/// filesystem cannot be inspected at all (distinct from a normal "not
/// downloaded yet" result, which is a status value, not an exception).
class ModelDownloadException extends AppException {
  const ModelDownloadException(super.message, {super.cause});
}
