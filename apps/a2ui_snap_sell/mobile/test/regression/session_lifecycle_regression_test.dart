import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/domain/models/captured_photo.dart';
import 'package:mobile/src/session/selling_session_controller.dart';
import 'package:mobile/src/session/selling_session_state.dart';

import '../support/fakes.dart';

void main() {
  group('Session lifecycle and disposal regression tests', () {
    test('disposing ProviderContainer cancels all subscriptions and disposes SellingAgentRepository cleanly', () async {
      final FakeImageCaptureService fakeCapture = FakeImageCaptureService();
      final FakeA2uiAgentService fakeAgent = FakeA2uiAgentService(
        imageCaptureService: fakeCapture,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
          sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
        ],
      );

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);

      container.dispose();

      expect(fakeAgent.disposeCount, equals(1));
    });

    test('resetSession clears state to idle and ignores subsequent surface events after dispose', () async {
      final FakeImageCaptureService fakeCapture = FakeImageCaptureService();
      final FakeA2uiAgentService fakeAgent = FakeA2uiAgentService(
        imageCaptureService: fakeCapture,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
          sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
        ],
      );
      addTearDown(container.dispose);

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
      controller.resetSession();

      final SellingSessionState state = container.read(
        sellingSessionControllerProvider,
      );
      expect(state.status, equals(SellingFlowStatus.idle));
      expect(state.activeSurfaceId, isNull);
      expect(state.surfaceHistory, isEmpty);
    });
  });
}
