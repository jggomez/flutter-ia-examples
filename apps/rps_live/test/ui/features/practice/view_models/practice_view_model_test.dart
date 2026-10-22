import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/repositories/classifier_repository.dart';
import 'package:rps_live/ui/features/practice/view_models/practice_view_model.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

const _result1 = ClassificationResult(
  paperConfidence: 0.7,
  rockConfidence: 0.2,
  scissorsConfidence: 0.1,
);
const _result2 = ClassificationResult(
  paperConfidence: 0.1,
  rockConfidence: 0.1,
  scissorsConfidence: 0.8,
);

/// `build()` reaches its `classificationStream.listen(...)` call only after
/// an `await` (on `classifierRepository.initialize()`); emitting on the
/// fake's broadcast stream before that subscription is attached would be
/// silently dropped (no listener yet). Flushing the microtask queue first
/// guarantees `build()` has reached the `.listen(...)` call.
Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  group('PracticeViewModel', () {
    test('initializes the classifier and resolves with the first emitted '
        'classification', () async {
      final classifier = FakeClassifierRepository();
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      );
      addTearDown(container.dispose);
      // `practiceViewModelProvider` is `.autoDispose` (see the addendum
      // to doc/adr/0001-state-management-riverpod.md): without an active
      // listener, Riverpod would tear it down between the `await`s this
      // test uses. Holding a no-op listener keeps it alive, the standard
      // pattern for testing `autoDispose` providers.
      container.listen(practiceViewModelProvider, (_, _) {});

      final future = container.read(practiceViewModelProvider.future);
      await _flushMicrotasks();
      classifier.emit(_result1);
      final value = await future;

      expect(value, _result1);
      expect(classifier.initializeCallCount, 1);
      expect(
        container.read(practiceViewModelProvider),
        const AsyncData<ClassificationResult?>(_result1),
      );
    });

    test('subsequent emissions update state without re-initializing', () async {
      final classifier = FakeClassifierRepository();
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      );
      addTearDown(container.dispose);
      // `practiceViewModelProvider` is `.autoDispose` (see the addendum
      // to doc/adr/0001-state-management-riverpod.md): without an active
      // listener, Riverpod would tear it down between the `await`s this
      // test uses. Holding a no-op listener keeps it alive, the standard
      // pattern for testing `autoDispose` providers.
      container.listen(practiceViewModelProvider, (_, _) {});

      final future = container.read(practiceViewModelProvider.future);
      await _flushMicrotasks();
      classifier.emit(_result1);
      await future;

      classifier.emit(_result2);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(practiceViewModelProvider),
        const AsyncData<ClassificationResult?>(_result2),
      );
      expect(classifier.initializeCallCount, 1);
    });

    test('surfaces an initialize() failure as AsyncError', () async {
      final classifier = FakeClassifierRepository()
        ..initializeError = const ModelAssetNotFoundException(
          'rps_model.tflite is missing.',
        );
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      );
      addTearDown(container.dispose);
      // `practiceViewModelProvider` is `.autoDispose` (see the addendum
      // to doc/adr/0001-state-management-riverpod.md): without an active
      // listener, Riverpod would tear it down between the `await`s this
      // test uses. Holding a no-op listener keeps it alive, the standard
      // pattern for testing `autoDispose` providers.
      container.listen(practiceViewModelProvider, (_, _) {});

      await expectLater(
        container.read(practiceViewModelProvider.future),
        throwsA(isA<ModelAssetNotFoundException>()),
      );
      expect(container.read(practiceViewModelProvider).hasError, isTrue);
    });

    test('surfaces a mid-stream classification error as AsyncError', () async {
      final classifier = FakeClassifierRepository();
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      );
      addTearDown(container.dispose);
      // `practiceViewModelProvider` is `.autoDispose` (see the addendum
      // to doc/adr/0001-state-management-riverpod.md): without an active
      // listener, Riverpod would tear it down between the `await`s this
      // test uses. Holding a no-op listener keeps it alive, the standard
      // pattern for testing `autoDispose` providers.
      container.listen(practiceViewModelProvider, (_, _) {});

      final future = container.read(practiceViewModelProvider.future);
      await _flushMicrotasks();
      classifier.emit(_result1);
      await future;

      classifier.emitError(const CameraUnavailableException('lost camera'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(practiceViewModelProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<CameraUnavailableException>());
    });

    test('cancels its stream subscription on dispose', () async {
      final classifier = FakeClassifierRepository();
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      );
      // `practiceViewModelProvider` is `.autoDispose` (see the addendum to
      // doc/adr/0001-state-management-riverpod.md): without an active
      // listener, Riverpod would tear it down between the `await`s this
      // test uses. Holding a no-op listener keeps it alive, the standard
      // pattern for testing `autoDispose` providers.
      container.listen(practiceViewModelProvider, (_, _) {});

      final future = container.read(practiceViewModelProvider.future);
      await _flushMicrotasks();
      classifier.emit(_result1);
      await future;

      container.dispose();

      // No crash/late-listener error emitting after dispose.
      classifier.emit(_result2);
    });

    test(
      'switchCamera() delegates to ClassifierRepository.switchCamera()',
      () async {
        final classifier = FakeClassifierRepository();
        final container = ProviderContainer(
          overrides: [
            classifierRepositoryProvider.overrideWithValue(classifier),
          ],
        );
        addTearDown(container.dispose);
        container.listen(practiceViewModelProvider, (_, _) {});

        final future = container.read(practiceViewModelProvider.future);
        await _flushMicrotasks();
        classifier.emit(_result1);
        await future;

        await container.read(practiceViewModelProvider.notifier).switchCamera();
        expect(classifier.switchCameraCallCount, 1);
      },
    );
  });
}
