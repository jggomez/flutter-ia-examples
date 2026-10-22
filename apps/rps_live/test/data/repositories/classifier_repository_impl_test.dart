import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/data/repositories/classifier_repository_impl.dart';

import '../../support/fakes.dart';

/// Exercises `ClassifierRepositoryImpl.initialize()`/`dispose()` directly
/// against fake *services* (not a fake repository), the level at which
/// `flutter-reviewer`'s Bug 1 (camera-owning provider lifecycle leak)
/// actually lives: a `FakeClassifierRepository` (used by the view-model
/// tests) has a trivially idempotent `initialize()`/`dispose()` by
/// construction, so it can never catch a bug in the real
/// `ClassifierRepositoryImpl`'s bookkeeping.
void main() {
  group('ClassifierRepositoryImpl lifecycle', () {
    test(
      'initialize() then dispose() then initialize() again cleanly '
      'reloads the interpreter and restarts the camera exactly once each',
      () async {
        final camera = FakeCameraFrameService();
        final classifierService = FakeTfliteClassifierService();
        final repository = ClassifierRepositoryImpl(
          cameraFrameService: camera,
          classifierService: classifierService,
        );

        await repository.initialize();
        expect(classifierService.loadCallCount, 1);
        expect(camera.startCallCount, 1);
        expect(camera.listenerCount, 1);

        await repository.dispose();
        expect(classifierService.disposeCallCount, 1);
        expect(camera.stopCallCount, 1);
        expect(camera.listenerCount, 0);

        await repository.initialize();
        expect(classifierService.loadCallCount, 2);
        expect(camera.startCallCount, 2);
        expect(camera.listenerCount, 1);

        await repository.dispose();
        expect(classifierService.disposeCallCount, 2);
        expect(camera.listenerCount, 0);
      },
    );

    test('dispose() without a prior initialize() is a safe no-op', () async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService();
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );

      await repository.dispose();

      expect(classifierService.disposeCallCount, 0);
      expect(camera.stopCallCount, 0);
    });

    test('dispose() is safe to call twice in a row', () async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService();
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );

      await repository.initialize();
      await repository.dispose();
      await repository.dispose();

      expect(classifierService.disposeCallCount, 1);
      expect(camera.stopCallCount, 1);
    });

    test('a second initialize() while the first is still active shares the '
        'running session instead of reloading the interpreter/restarting the '
        'camera, and only the matching number of dispose() calls tears it '
        'down (reference counting)', () async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService();
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );

      // Simulates the real app's tab-switch race: the incoming screen's
      // initialize() can run before the outgoing screen's dispose() (see
      // the doc comment on `ClassifierRepositoryImpl._activeSessions`).
      await repository.initialize(); // caller A (e.g. VsAiViewModel)
      await repository.initialize(); // caller B (e.g. PracticeViewModel)

      expect(
        classifierService.loadCallCount,
        1,
        reason:
            'the interpreter must not be reloaded for an overlapping '
            'caller',
      );
      expect(camera.startCallCount, 1);
      expect(camera.listenerCount, 1);

      await repository.dispose(); // caller A leaves
      expect(
        classifierService.disposeCallCount,
        0,
        reason:
            'caller B is still relying on the session; it must not be '
            'torn down underneath it',
      );
      expect(camera.listenerCount, 1);

      await repository.dispose(); // caller B leaves
      expect(classifierService.disposeCallCount, 1);
      expect(camera.stopCallCount, 1);
      expect(camera.listenerCount, 0);
    });

    test('a failed initialize() rolls back so a later initialize() is not '
        'wedged in a partially-initialized state', () async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService()
        ..loadError = Exception('model asset missing');
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );

      await expectLater(repository.initialize(), throwsException);
      expect(camera.startCallCount, 0);

      classifierService.loadError = null;
      await repository.initialize();

      expect(classifierService.loadCallCount, 2);
      expect(camera.startCallCount, 1);
      expect(camera.listenerCount, 1);
    });

    test(
      'switchCamera() delegates to CameraFrameService.switchCamera()',
      () async {
        final camera = FakeCameraFrameService();
        final classifierService = FakeTfliteClassifierService();
        final repository = ClassifierRepositoryImpl(
          cameraFrameService: camera,
          classifierService: classifierService,
        );

        await repository.initialize();
        await repository.switchCamera();

        expect(camera.switchCameraCallCount, 1);
      },
    );
  });
}
