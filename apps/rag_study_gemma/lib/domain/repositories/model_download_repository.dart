import '../../core/error/app_exception.dart';
import '../models/model_download_status.dart';

/// Thrown when downloading or verifying on-device model artifacts fails.
class ModelDownloadException extends AppException {
  const ModelDownloadException(super.message, {super.cause});
}

/// Thrown when attempting to download models without an active Wi-Fi connection.
class WifiRequiredException extends ModelDownloadException {
  const WifiRequiredException(super.message, {super.cause});
}

/// Thrown when HuggingFace rejects authentication or gated repository access.
class HuggingFaceAuthException extends ModelDownloadException {
  const HuggingFaceAuthException(super.message, {super.cause});
}

/// Contract for verifying Wi-Fi, checking readiness, and downloading the dual models.
abstract interface class ModelDownloadRepository {
  Future<bool> areModelsReady();

  Future<bool> isUnmeteredWifi();

  Stream<ModelDownloadStatus> downloadModels({String? hfToken});

  Future<void> deleteModels();
}
