import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/repositories/model_download_repository_impl.dart';
import 'package:rag_study_gemma/data/services/app_storage_service.dart';
import 'package:rag_study_gemma/data/services/model_download_service.dart';
import 'package:rag_study_gemma/data/services/network_connectivity_service.dart';
import 'package:rag_study_gemma/domain/models/model_download_status.dart';
import 'package:rag_study_gemma/domain/use_cases/validate_downloaded_models_use_case.dart';

class _TempAppStorageService implements AppStorageService {
  _TempAppStorageService(this.dir);

  final Directory dir;

  @override
  Future<String> get embeddingModelFilePath async =>
      '${dir.path}/embeddinggemma-2-text-270m.litertlm';

  @override
  Future<String> get llmModelFilePath async =>
      '${dir.path}/gemma-4-E2B-it.litertlm';

  @override
  Future<String> get ragSqliteDbPath async =>
      '${dir.path}/study_gemma_rag.sqlite';
}

class _FakeConnectivityService implements NetworkConnectivityService {
  bool wifi = true;

  @override
  Future<bool> isWifiConnected() async => wifi;
}

class _FakeModelDownloadService implements ModelDownloadService {
  final List<Uri> downloadedUrls = [];
  final List<Uri?> fallbackUrls = [];
  int bytesToWrite = 1024;
  Object? error;

  @override
  Stream<ModelDownloadProgress> downloadToFile({
    required Uri url,
    required String destinationPath,
    Uri? fallbackUrl,
    String? hfToken,
  }) async* {
    if (error != null) throw error!;
    downloadedUrls.add(url);
    fallbackUrls.add(fallbackUrl);
    final file = File(destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytesToWrite, 1));
    yield ModelDownloadProgress(
      bytesReceived: bytesToWrite ~/ 2,
      totalBytes: bytesToWrite,
    );
    yield ModelDownloadProgress(
      bytesReceived: bytesToWrite,
      totalBytes: bytesToWrite,
    );
  }
}

void main() {
  group('ModelDownloadRepositoryImpl', () {
    late Directory tempDir;
    late _TempAppStorageService storageService;
    late _FakeConnectivityService connectivityService;
    late _FakeModelDownloadService downloadService;
    late ModelDownloadRepositoryImpl repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_dl_repo_test_');
      storageService = _TempAppStorageService(tempDir);
      connectivityService = _FakeConnectivityService();
      downloadService = _FakeModelDownloadService();
      repository = ModelDownloadRepositoryImpl(
        appStorageService: storageService,
        networkConnectivityService: connectivityService,
        modelDownloadService: downloadService,
        validateDownloadedModelsUseCase:
            const ValidateDownloadedModelsUseCase(),
        minEmbeddingModelBytes: 512,
        minLlmModelBytes: 512,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'emits failed status immediately when Wi-Fi is not connected',
      () async {
        connectivityService.wifi = false;

        final events = await repository.downloadModels().toList();
        expect(events, hasLength(1));
        expect(events.first.phase, equals(ModelDownloadPhase.failed));
        expect(events.first.errorMessage, contains('Wi-Fi'));
        expect(downloadService.downloadedUrls, isEmpty);
      },
    );

    test('sequentially downloads EmbeddingGemma 2 then Gemma 4 E2B IT and marks ready', () async {
      expect(await repository.areModelsReady(), isFalse);

      final events = await repository
          .downloadModels(hfToken: 'hf_abc')
          .toList();

      final phases = events.map((e) => e.phase).toList();
      expect(phases, contains(ModelDownloadPhase.downloadingEmbedding));
      expect(phases, contains(ModelDownloadPhase.downloadingLlm));
      expect(phases.last, equals(ModelDownloadPhase.ready));

      expect(downloadService.downloadedUrls, hasLength(2));
      expect(
        downloadService.downloadedUrls[0].toString(),
        contains('embeddinggemma-2-text-270m.litertlm'),
      );
      expect(
        downloadService.downloadedUrls[1].toString(),
        contains('gemma-4-E2B-it.litertlm'),
      );
      expect(
        downloadService.fallbackUrls[1].toString(),
        equals(
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/'
          'gemma-4-E2B-it.litertlm',
        ),
      );

      expect(await repository.areModelsReady(), isTrue);

      await repository.deleteModels();
      expect(await repository.areModelsReady(), isFalse);
    });

    test(
      'skips Stage 1 download when EmbeddingGemma 2 is already valid on disk',
      () async {
        final embeddingPath = await storageService.embeddingModelFilePath;
        await File(embeddingPath).writeAsBytes(List<int>.filled(600, 7));

        final events = await repository.downloadModels().toList();
        expect(events.last.phase, equals(ModelDownloadPhase.ready));
        expect(downloadService.downloadedUrls, hasLength(1));
        expect(
          downloadService.downloadedUrls.single.toString(),
          contains('gemma-4-E2B-it.litertlm'),
        );
      },
    );
  });
}
