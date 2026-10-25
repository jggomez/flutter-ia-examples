// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import '../../core/error/app_exception.dart';
import '../../domain/models/model_download_status.dart';
import '../../domain/repositories/model_download_repository.dart';
import '../../domain/use_cases/validate_downloaded_models_use_case.dart';
import '../services/app_storage_service.dart';
import '../services/model_download_service.dart';
import '../services/network_connectivity_service.dart';

/// Implementation of [ModelDownloadRepository] orchestrating the Wi-Fi-gated,
/// sequential two-stage download of `EmbeddingGemma 2` and `Gemma 3 1B IT`.
class ModelDownloadRepositoryImpl implements ModelDownloadRepository {
  ModelDownloadRepositoryImpl({
    AppStorageService? appStorageService,
    NetworkConnectivityService networkConnectivityService =
        const NetworkConnectivityServiceImpl(),
    ModelDownloadService? modelDownloadService,
    ValidateDownloadedModelsUseCase validateDownloadedModelsUseCase =
        const ValidateDownloadedModelsUseCase(),
    Uri? embeddingModelUrl,
    Uri? llmModelUrl,
    Uri? llmFallbackUrl,
    int? minEmbeddingModelBytes,
    int? minLlmModelBytes,
  }) : _appStorageService = appStorageService ?? AppStorageServiceImpl(),
       _networkConnectivityService = networkConnectivityService,
       _modelDownloadService =
           modelDownloadService ?? ModelDownloadServiceImpl(),
       _validateDownloadedModelsUseCase = validateDownloadedModelsUseCase,
       _embeddingModelUrl = embeddingModelUrl ?? defaultEmbeddingModelUrl,
       _llmModelUrl = llmModelUrl ?? defaultLlmModelUrl,
       _llmFallbackUrl = llmFallbackUrl ?? defaultLlmFallbackUrl,
       _minEmbeddingModelBytes =
           minEmbeddingModelBytes ??
           ValidateDownloadedModelsUseCase.minEmbeddingModelSizeBytes,
       _minLlmModelBytes =
           minLlmModelBytes ??
           ValidateDownloadedModelsUseCase.minLlmModelSizeBytes;

  static final Uri defaultEmbeddingModelUrl = Uri.parse(
    'https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/'
    'resolve/9be6e8b90982095dc05c2bd162e4b954ee4dbac7/'
    'embeddinggemma-2-text-270m.litertlm',
  );

  static final Uri defaultLlmModelUrl = Uri.parse(
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/'
    'gemma-4-E2B-it.litertlm',
  );

  static final Uri defaultLlmFallbackUrl = Uri.parse(
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/'
    'gemma-4-E2B-it.litertlm',
  );

  static const String embeddingDisplayName = 'EmbeddingGemma 2 (270M)';
  static const String llmDisplayName = 'Gemma 4 E2B IT';

  final AppStorageService _appStorageService;
  final NetworkConnectivityService _networkConnectivityService;
  final ModelDownloadService _modelDownloadService;
  final ValidateDownloadedModelsUseCase _validateDownloadedModelsUseCase;
  final Uri _embeddingModelUrl;
  final Uri _llmModelUrl;
  final Uri _llmFallbackUrl;
  final int _minEmbeddingModelBytes;
  final int _minLlmModelBytes;

  @override
  Future<bool> areModelsReady() async {
    try {
      final embeddingFile = File(
        await _appStorageService.embeddingModelFilePath,
      );
      final llmFile = File(await _appStorageService.llmModelFilePath);

      final embeddingExists = await embeddingFile.exists();
      final llmExists = await llmFile.exists();
      final embeddingBytes = embeddingExists ? await embeddingFile.length() : 0;
      final llmBytes = llmExists ? await llmFile.length() : 0;

      return _validateDownloadedModelsUseCase(
        embeddingExists: embeddingExists,
        embeddingByteLength: embeddingBytes,
        llmExists: llmExists,
        llmByteLength: llmBytes,
        minEmbeddingBytes: _minEmbeddingModelBytes,
        minLlmBytes: _minLlmModelBytes,
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelDownloadException(
          'Failed to verify downloaded models on disk.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<bool> isUnmeteredWifi() =>
      _networkConnectivityService.isWifiConnected();

  @override
  Stream<ModelDownloadStatus> downloadModels({String? hfToken}) {
    final controller = StreamController<ModelDownloadStatus>();

    Future<void> run() async {
      try {
        if (!await _networkConnectivityService.isWifiConnected()) {
          controller.add(
            const ModelDownloadStatus(
              phase: ModelDownloadPhase.failed,
              errorMessage:
                  'Active Wi-Fi connection required to download the ~2.74 GB '
                  'on-device AI models. Please connect to Wi-Fi and try again.',
            ),
          );
          await controller.close();
          return;
        }

        // Stage 1: EmbeddingGemma 2 (~157 MB)
        final embeddingPath = await _appStorageService.embeddingModelFilePath;
        final embeddingFile = File(embeddingPath);
        final embeddingAlreadyReady =
            await embeddingFile.exists() &&
            _validateDownloadedModelsUseCase.isValidEmbeddingModel(
              await embeddingFile.length(),
              minBytes: _minEmbeddingModelBytes,
            );

        if (!embeddingAlreadyReady) {
          controller.add(
            const ModelDownloadStatus(
              phase: ModelDownloadPhase.downloadingEmbedding,
              bytesReceived: 0,
              totalBytes: 0,
              currentModelName: embeddingDisplayName,
            ),
          );

          await for (final progress in _modelDownloadService.downloadToFile(
            url: _embeddingModelUrl,
            destinationPath: embeddingPath,
            hfToken: hfToken,
          )) {
            controller.add(
              ModelDownloadStatus(
                phase: ModelDownloadPhase.downloadingEmbedding,
                bytesReceived: progress.bytesReceived,
                totalBytes: progress.totalBytes,
                currentModelName: embeddingDisplayName,
              ),
            );
          }

          final downloadedSize = await embeddingFile.exists()
              ? await embeddingFile.length()
              : 0;
          if (!_validateDownloadedModelsUseCase.isValidEmbeddingModel(
            downloadedSize,
            minBytes: _minEmbeddingModelBytes,
          )) {
            if (await embeddingFile.exists()) {
              await embeddingFile.delete();
            }
            throw const ModelDownloadException(
              'Downloaded EmbeddingGemma 2 file is smaller than expected and may be corrupted.',
            );
          }
        }

        // Stage 2: Gemma 4 E2B IT (~2.58 GB)
        final llmPath = await _appStorageService.llmModelFilePath;
        final llmFile = File(llmPath);
        final llmAlreadyReady =
            await llmFile.exists() &&
            _validateDownloadedModelsUseCase.isValidLlmModel(
              await llmFile.length(),
              minBytes: _minLlmModelBytes,
            );

        if (!llmAlreadyReady) {
          controller.add(
            const ModelDownloadStatus(
              phase: ModelDownloadPhase.downloadingLlm,
              bytesReceived: 0,
              totalBytes: 0,
              currentModelName: llmDisplayName,
            ),
          );

          await for (final progress in _modelDownloadService.downloadToFile(
            url: _llmModelUrl,
            fallbackUrl: _llmFallbackUrl,
            destinationPath: llmPath,
            hfToken: hfToken,
          )) {
            controller.add(
              ModelDownloadStatus(
                phase: ModelDownloadPhase.downloadingLlm,
                bytesReceived: progress.bytesReceived,
                totalBytes: progress.totalBytes,
                currentModelName: llmDisplayName,
              ),
            );
          }

          final downloadedSize = await llmFile.exists()
              ? await llmFile.length()
              : 0;
          if (!_validateDownloadedModelsUseCase.isValidLlmModel(
            downloadedSize,
            minBytes: _minLlmModelBytes,
          )) {
            if (await llmFile.exists()) {
              await llmFile.delete();
            }
            throw const ModelDownloadException(
              'Downloaded Gemma 4 E2B IT file is smaller than expected and may be corrupted.',
            );
          }
        }

        final finalLlmBytes = await llmFile.length();
        controller.add(
          ModelDownloadStatus(
            phase: ModelDownloadPhase.ready,
            bytesReceived: finalLlmBytes,
            totalBytes: finalLlmBytes,
            currentModelName: llmDisplayName,
          ),
        );
        await controller.close();
      } catch (error) {
        final message = error is AppException
            ? error.message
            : error.toString();
        controller.add(
          ModelDownloadStatus(
            phase: ModelDownloadPhase.failed,
            errorMessage: message,
          ),
        );
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  @override
  Future<void> deleteModels() async {
    try {
      final embeddingPath = await _appStorageService.embeddingModelFilePath;
      final llmPath = await _appStorageService.llmModelFilePath;
      for (final path in [
        embeddingPath,
        '$embeddingPath.part',
        llmPath,
        '$llmPath.part',
      ]) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelDownloadException(
          'Failed to delete local model files.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}
