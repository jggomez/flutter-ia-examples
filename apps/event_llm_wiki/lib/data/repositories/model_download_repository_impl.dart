// See `agenda_repository_impl.dart`'s matching comment: named-parameter
// fields are assigned manually (not via initializing formals) so
// `main.dart` can still pass them by name.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../domain/models/model_download_status.dart';
import '../../domain/repositories/model_download_repository.dart';
import '../../domain/use_cases/validate_downloaded_model_use_case.dart';
import '../services/app_storage_service.dart';
import '../services/model_download_service.dart';

/// [ModelDownloadRepository] composed from [ModelDownloadService] (streamed
/// HTTP bytes) + [AppStorageService] (filesystem paths/ops) +
/// [ValidateDownloadedModelUseCase] (min-size sanity check).
///
/// See `doc/adr/0005-model-download-flow.md` for the one-shot,
/// non-resumable download design [download] implements: delete any leftover
/// `.part` file first, stream fresh bytes into a new `.part` file, validate,
/// atomically rename.
class ModelDownloadRepositoryImpl implements ModelDownloadRepository {
  ModelDownloadRepositoryImpl({
    required ModelDownloadService modelDownloadService,
    required AppStorageService appStorageService,
    required Uri modelUrl,
    this.validateDownloadedModelUseCase =
        const ValidateDownloadedModelUseCase(),
  }) : _modelDownloadService = modelDownloadService,
       _appStorageService = appStorageService,
       _modelUrl = modelUrl;

  final ModelDownloadService _modelDownloadService;
  final AppStorageService _appStorageService;

  /// Download URL for `litert-community/Gemma3-1B-IT`'s `.litertlm` file
  /// (see `doc/adr/0001-llm-runtime-model-selection.md`).
  final Uri _modelUrl;

  final ValidateDownloadedModelUseCase validateDownloadedModelUseCase;

  @override
  Future<ModelDownloadStatus> checkLocalStatus() async {
    try {
      final sizeBytes = await _appStorageService.modelFileSizeBytes();
      if (sizeBytes != null &&
          validateDownloadedModelUseCase(fileSizeBytes: sizeBytes)) {
        return const ModelDownloadStatus(phase: ModelDownloadPhase.ready);
      }
      // No file, or a file that fails the size sanity check — either way,
      // not ready. A leftover `.part` file is intentionally NOT inspected
      // here: it is never resumed, only discarded at the start of the next
      // `download()` call (see the ADR).
      return const ModelDownloadStatus(phase: ModelDownloadPhase.notDownloaded);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelDownloadException(
          'Failed to check local model download status.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<ModelDownloadStatus> download() {
    final controller = StreamController<ModelDownloadStatus>();

    Future<void> run() async {
      var bytesDownloaded = 0;
      try {
        await _appStorageService.deletePartFileIfExists();

        await for (final chunk in _modelDownloadService.download(_modelUrl)) {
          await _appStorageService.appendToPartFile(chunk.bytes);
          bytesDownloaded += chunk.bytes.length;
          controller.add(
            ModelDownloadStatus(
              phase: ModelDownloadPhase.downloading,
              bytesDownloaded: bytesDownloaded,
              totalBytes: chunk.totalBytes,
            ),
          );
        }
        await _appStorageService.closePartFileWriter();

        if (!validateDownloadedModelUseCase(fileSizeBytes: bytesDownloaded)) {
          await _appStorageService.deletePartFileIfExists();
          controller.add(
            const ModelDownloadStatus(
              phase: ModelDownloadPhase.failed,
              errorMessage:
                  'Downloaded file is smaller than the minimum plausible '
                  'model size — the download was likely interrupted.',
            ),
          );
          await controller.close();
          return;
        }

        await _appStorageService.renamePartFileToModelFile();
        controller.add(
          const ModelDownloadStatus(phase: ModelDownloadPhase.ready),
        );
        await controller.close();
      } catch (error) {
        await _appStorageService.closePartFileWriter();
        controller.add(
          ModelDownloadStatus(
            phase: ModelDownloadPhase.failed,
            errorMessage: error.toString(),
          ),
        );
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }
}
