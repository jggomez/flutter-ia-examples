import 'package:event_gemma/domain/models/model_download_status.dart';
import 'package:event_gemma/ui/features/setup/view_models/model_download_view_model.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fakes.dart';

void main() {
  group('ModelDownloadViewModel', () {
    test('build() checks local status without starting a download', () async {
      final repository = FakeModelDownloadRepository()
        ..localStatus = const ModelDownloadStatus(
          phase: ModelDownloadPhase.ready,
        );
      final container = ProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final status = await container.read(
        modelDownloadViewModelProvider.future,
      );

      expect(status.phase, ModelDownloadPhase.ready);
      expect(repository.downloadCallCount, 0);
    });

    test(
      'build() reports notDownloaded when checkLocalStatus says so',
      () async {
        final repository = FakeModelDownloadRepository();
        final container = ProviderContainer(
          overrides: [
            modelDownloadRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);

        final status = await container.read(
          modelDownloadViewModelProvider.future,
        );

        expect(status.phase, ModelDownloadPhase.notDownloaded);
      },
    );

    test('startDownload() pushes each download() event into state', () async {
      final repository = FakeModelDownloadRepository()
        ..downloadEvents = const [
          ModelDownloadStatus(
            phase: ModelDownloadPhase.downloading,
            bytesDownloaded: 50,
            totalBytes: 100,
          ),
          ModelDownloadStatus(
            phase: ModelDownloadPhase.downloading,
            bytesDownloaded: 100,
            totalBytes: 100,
          ),
          ModelDownloadStatus(phase: ModelDownloadPhase.ready),
        ];
      final container = ProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(modelDownloadViewModelProvider.future);

      final seenPhases = <ModelDownloadPhase>[];
      container.listen(modelDownloadViewModelProvider, (previous, next) {
        next.whenData((status) => seenPhases.add(status.phase));
      });

      await container
          .read(modelDownloadViewModelProvider.notifier)
          .startDownload();

      expect(seenPhases.last, ModelDownloadPhase.ready);
      expect(
        container.read(modelDownloadViewModelProvider).value?.phase,
        ModelDownloadPhase.ready,
      );
    });

    test('startDownload() surfaces a failed status without throwing', () async {
      final repository = FakeModelDownloadRepository()
        ..downloadEvents = const [
          ModelDownloadStatus(
            phase: ModelDownloadPhase.failed,
            errorMessage: 'network error',
          ),
        ];
      final container = ProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(modelDownloadViewModelProvider.future);

      await container
          .read(modelDownloadViewModelProvider.notifier)
          .startDownload();

      final status = container.read(modelDownloadViewModelProvider).value;
      expect(status?.phase, ModelDownloadPhase.failed);
      expect(status?.errorMessage, 'network error');
    });

    test('checkWifiConnected() queries repository and startDownload() '
        'forwards authToken', () async {
      final repository = FakeModelDownloadRepository()..wifiConnected = false;
      final container = ProviderContainer(
        overrides: [
          modelDownloadRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(modelDownloadViewModelProvider.future);

      final notifier = container.read(modelDownloadViewModelProvider.notifier);
      expect(await notifier.checkWifiConnected(), isFalse);

      await notifier.startDownload(authToken: 'hf_abc');
      expect(repository.lastAuthToken, 'hf_abc');
    });
  });
}
