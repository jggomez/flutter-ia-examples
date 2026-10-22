import 'dart:async';
import 'dart:typed_data';

import 'package:event_gemma/data/repositories/model_download_repository_impl.dart';
import 'package:event_gemma/data/services/app_storage_service.dart';
import 'package:event_gemma/data/services/model_download_service.dart';
import 'package:event_gemma/domain/models/model_download_status.dart';
import 'package:event_gemma/domain/use_cases/validate_downloaded_model_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// In-memory [AppStorageService] fake — a `Map<String, List<int>>` stands
/// in for the filesystem, no real device storage involved.
class _FakeAppStorageService implements AppStorageService {
  final Map<String, List<int>> files = {};
  int deletePartFileCallCount = 0;
  int renameCallCount = 0;

  @override
  Future<String> get modelFilePath async => 'model.litertlm';

  @override
  Future<String> get modelPartFilePath async => 'model.litertlm.part';

  @override
  Future<bool> modelFileExists() async => files.containsKey('model.litertlm');

  @override
  Future<int?> modelFileSizeBytes() async => files['model.litertlm']?.length;

  @override
  Future<void> deletePartFileIfExists() async {
    deletePartFileCallCount++;
    files.remove('model.litertlm.part');
  }

  @override
  Future<void> appendToPartFile(List<int> bytes) async {
    final existing = files['model.litertlm.part'];
    // Tracked as a byte COUNT, not the literal bytes, so tests can simulate
    // realistic (~100 MB+) download sizes without actually allocating that
    // much memory per test.
    files['model.litertlm.part'] = List.filled(
      (existing?.length ?? 0) + bytes.length,
      0,
      growable: false,
    );
  }

  @override
  Future<void> closePartFileWriter() async {}

  @override
  Future<void> renamePartFileToModelFile() async {
    renameCallCount++;
    final part = files.remove('model.litertlm.part');
    if (part != null) files['model.litertlm'] = part;
  }
}

/// Canned-chunk [ModelDownloadService] fake — no real network call, per
/// PLAN.md phase 7.
class _FakeModelDownloadService implements ModelDownloadService {
  _FakeModelDownloadService(this.chunks);

  final List<ModelDownloadChunk> chunks;
  Object? error;
  Uri? lastRequestedUrl;
  String? lastAuthToken;

  @override
  Stream<ModelDownloadChunk> download(Uri modelUrl, {String? authToken}) {
    lastRequestedUrl = modelUrl;
    lastAuthToken = authToken;
    final controller = StreamController<ModelDownloadChunk>();
    scheduleMicrotask(() async {
      for (final chunk in chunks) {
        controller.add(chunk);
      }
      final err = error;
      if (err != null) {
        controller.addError(err);
      } else {
        await controller.close();
      }
    });
    return controller.stream;
  }
}

/// A single small placeholder chunk whose *reported* [totalBytes] simulates
/// a full ~100 MB+ download without allocating that many real bytes — only
/// [ModelDownloadChunk.bytes]' length feeds `bytesDownloaded` accounting
/// (see [_FakeAppStorageService.appendToPartFile]), so a `Uint8List` of the
/// real target length is used only where the byte COUNT itself matters.
ModelDownloadChunk _bigChunk(int sizeBytes) =>
    ModelDownloadChunk(bytes: Uint8List(sizeBytes), totalBytes: sizeBytes);

void main() {
  late _FakeAppStorageService storage;
  late _FakeModelDownloadService downloadService;
  late FakeNetworkConnectivityService connectivityService;
  final modelUrl = Uri.parse('https://example.com/model.litertlm');

  ModelDownloadRepositoryImpl makeRepository() {
    return ModelDownloadRepositoryImpl(
      modelDownloadService: downloadService,
      appStorageService: storage,
      networkConnectivityService: connectivityService,
      modelUrl: modelUrl,
      validateDownloadedModelUseCase: const ValidateDownloadedModelUseCase(),
    );
  }

  setUp(() {
    storage = _FakeAppStorageService();
    connectivityService = FakeNetworkConnectivityService();
    downloadService = _FakeModelDownloadService([
      ModelDownloadChunk(bytes: List.filled(60, 1), totalBytes: 120),
      ModelDownloadChunk(bytes: List.filled(60, 2), totalBytes: 120),
    ]);
  });

  group('checkLocalStatus', () {
    test('reports notDownloaded when no model file exists', () async {
      final repository = makeRepository();

      final status = await repository.checkLocalStatus();

      expect(status.phase, ModelDownloadPhase.notDownloaded);
    });

    test('reports ready when a validated model file exists', () async {
      storage.files['model.litertlm'] = List.filled(
        ValidateDownloadedModelUseCase.minValidSizeBytes,
        0,
        growable: false,
      );
      final repository = makeRepository();

      final status = await repository.checkLocalStatus();

      expect(status.phase, ModelDownloadPhase.ready);
    });

    test('reports notDownloaded (not ready) when the model file is too '
        'small to pass validation', () async {
      storage.files['model.litertlm'] = [1, 2, 3];
      final repository = makeRepository();

      final status = await repository.checkLocalStatus();

      expect(status.phase, ModelDownloadPhase.notDownloaded);
    });

    test('a leftover .part file with no valid model file is treated as '
        'notDownloaded (not resumed)', () async {
      storage.files['model.litertlm.part'] = [1, 2, 3];
      final repository = makeRepository();

      final status = await repository.checkLocalStatus();

      expect(status.phase, ModelDownloadPhase.notDownloaded);
    });
  });

  group('download', () {
    test('deletes any pre-existing .part file before starting', () async {
      storage.files['model.litertlm.part'] = [9, 9, 9];
      final repository = makeRepository();

      await repository.download().toList();

      // At least once, unconditionally, before the fresh download starts
      // (this fixture's own download total is below the validation
      // threshold, so the repository also deletes the resulting invalid
      // `.part` file afterward — see the "below the minimum size" test for
      // that behavior in isolation).
      expect(storage.deletePartFileCallCount, greaterThanOrEqualTo(1));
    });

    test('emits downloading progress events as chunks arrive', () async {
      final repository = makeRepository();

      final events = await repository.download().toList();

      final downloadingEvents = events
          .where((e) => e.phase == ModelDownloadPhase.downloading)
          .toList();
      expect(downloadingEvents, isNotEmpty);
      expect(downloadingEvents.last.bytesDownloaded, 120);
      expect(downloadingEvents.last.totalBytes, 120);
    });

    test('validates and atomically renames the .part file into place on '
        'success, ending with a ready event, deleting any pre-existing '
        '.part file exactly once before the fresh download started', () async {
      storage.files['model.litertlm.part'] = [9, 9, 9];
      downloadService = _FakeModelDownloadService([
        _bigChunk(ValidateDownloadedModelUseCase.minValidSizeBytes),
      ]);
      final repository = makeRepository();

      final events = await repository.download().toList();

      expect(events.last.phase, ModelDownloadPhase.ready);
      expect(storage.renameCallCount, 1);
      expect(storage.deletePartFileCallCount, 1);
      expect(
        (await repository.checkLocalStatus()).phase,
        ModelDownloadPhase.ready,
      );
    });

    test('a download that completes below the minimum size ends with a '
        'failed event and does not rename the .part file', () async {
      downloadService = _FakeModelDownloadService([
        ModelDownloadChunk(bytes: [1, 2, 3], totalBytes: 3),
      ]);
      final repository = ModelDownloadRepositoryImpl(
        modelDownloadService: downloadService,
        appStorageService: storage,
        networkConnectivityService: connectivityService,
        modelUrl: modelUrl,
      );

      final events = await repository.download().toList();

      expect(events.last.phase, ModelDownloadPhase.failed);
      expect(events.last.errorMessage, isNotNull);
      expect(storage.renameCallCount, 0);
    });

    test('a network error mid-stream ends with a failed event, never '
        'throwing to the subscriber', () async {
      downloadService.error = Exception('connection reset');
      final repository = makeRepository();

      final events = await repository.download().toList();

      expect(events.last.phase, ModelDownloadPhase.failed);
      expect(events.last.errorMessage, contains('connection reset'));
    });

    test('requests the configured modelUrl and forwards authToken', () async {
      final repository = makeRepository();

      await repository.download(authToken: 'hf_custom').toList();

      expect(downloadService.lastRequestedUrl, modelUrl);
      expect(downloadService.lastAuthToken, 'hf_custom');
    });

    test('fails immediately without starting HTTP download when Wi-Fi is '
        'not connected', () async {
      connectivityService.wifiConnected = false;
      final repository = makeRepository();

      final events = await repository.download().toList();

      expect(events, hasLength(1));
      expect(events.single.phase, ModelDownloadPhase.failed);
      expect(events.single.errorMessage, contains('Wi-Fi'));
      expect(downloadService.lastRequestedUrl, isNull);
    });
  });
}
