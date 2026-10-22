import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/domain/models/captured_photo.dart';
import 'package:mobile/src/session/selling_session_controller.dart';
import 'package:mobile/src/session/selling_session_state.dart';

import '../support/fakes.dart';

void main() {
  group('SellingSessionController', () {
    late FakeImageCaptureService fakeCapture;
    late FakeA2uiAgentService fakeAgent;
    late ProviderContainer container;

    setUp(() {
      fakeCapture = FakeImageCaptureService();
      fakeAgent = FakeA2uiAgentService(imageCaptureService: fakeCapture);
      container = ProviderContainer(
        overrides: [
          imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
          sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('starts in idle state with no active surface', () {
      final SellingSessionState state = container.read(
        sellingSessionControllerProvider,
      );
      expect(state.status, equals(SellingFlowStatus.idle));
      expect(state.activeSurfaceId, isNull);
      expect(state.surfaceHistory, isEmpty);
    });

    test('startSessionWithPhoto captures photo, calls startSession, and activates surface from agent response', () async {
      final List<Object?> rawStep1 = jsonDecode(
        File('../contracts/examples/0.9/01_detected_car.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.cannedStartMessages = rawStep1.cast<Map<String, Object?>>();

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeCapture.capturedSources,
        equals(<PhotoCaptureSource>[PhotoCaptureSource.camera]),
      );
      expect(fakeAgent.startedPhotos, hasLength(1));
      expect(
        fakeAgent.startedPrompts.single,
        equals('Analyze this item and start the selling wizard.'),
      );

      final SellingSessionState state = container.read(
        sellingSessionControllerProvider,
      );
      expect(state.status, equals(SellingFlowStatus.activeSurface));
      expect(state.activeSurfaceId, equals('selling_step_1_detected'));
      expect(state.localPhotos['initial'], isNotNull);
    });

    test('attaches queued follow-up photo when SurfaceController.onSubmit emits an action', () async {
      final List<Object?> rawStep2 = jsonDecode(
        File('../contracts/examples/0.9/02_followup_damage_odometer.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.cannedStartMessages = rawStep2.cast<Map<String, Object?>>();

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
      await Future<void>.delayed(Duration.zero);

      final CapturedPhoto followupPhoto = CapturedPhoto(
        bytes: kFakeTransparentPng,
        mimeType: 'image/jpeg',
        fileName: 'odometer.jpg',
        source: PhotoCaptureSource.camera,
      );
      fakeCapture.queueFollowupPhoto(followupPhoto);

      fakeAgent.surfaceController
          .contextFor('selling_step_2_followup')
          .handleUiEvent(
            UserActionEvent(
              surfaceId: 'selling_step_2_followup',
              name: 'submit_followup_photo',
              sourceComponentId: 'req_odometer',
              context: <String, Object?>{'target': 'odometer'},
            ),
          );

      await Future<void>.delayed(Duration.zero);

      expect(fakeAgent.sentActions, hasLength(1));
      expect(fakeAgent.sentFollowupPhotos.single, same(followupPhoto));
    });

    test(
      'updates activeSurfaceId when a surface is removed via deleteSurface',
      () async {
        final SellingSessionController controller = container.read(
          sellingSessionControllerProvider.notifier,
        );
        await controller.startSessionWithPhoto(PhotoCaptureSource.gallery);

        fakeAgent.emitJsonMessages(<Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'surface_a',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'surface_b',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
            },
          },
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(sellingSessionControllerProvider).activeSurfaceId,
          equals('surface_b'),
        );

        fakeAgent.emitJsonMessages(<Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'deleteSurface': <String, Object?>{'surfaceId': 'surface_b'},
          },
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(sellingSessionControllerProvider).activeSurfaceId,
          equals('surface_a'),
        );
      },
    );

    test(
      'ignores duplicate startSessionWithPhoto calls while already processing',
      () async {
        final SellingSessionController controller = container.read(
          sellingSessionControllerProvider.notifier,
        );

        // Trigger first call without awaiting completion immediately
        final Future<void> firstCall = controller.startSessionWithPhoto(
          PhotoCaptureSource.camera,
        );
        expect(
          container.read(sellingSessionControllerProvider).isProcessing,
          isTrue,
        );

        // Trigger second call while still processing
        final Future<void> secondCall = controller.startSessionWithPhoto(
          PhotoCaptureSource.gallery,
        );

        await Future.wait(<Future<void>>[firstCall, secondCall]);

        expect(
          fakeCapture.capturedSources,
          equals(<PhotoCaptureSource>[PhotoCaptureSource.camera]),
        );
        expect(fakeAgent.startedPhotos, hasLength(1));
      },
    );

    test('ignores duplicate surface onSubmit calls while already processing (double-tap protection)', () async {
      final List<Object?> rawStep1 = jsonDecode(
        File('../contracts/examples/0.9/01_detected_car.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.cannedStartMessages = rawStep1.cast<Map<String, Object?>>();

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sellingSessionControllerProvider).isProcessing,
        isFalse,
      );

      final Completer<String?> actionCompleter = Completer<String?>();
      fakeAgent.customSendAction = (ChatMessage msg, CapturedPhoto? photo) {
        return actionCompleter.future;
      };

      // First submit
      fakeAgent.surfaceController
          .contextFor('selling_step_1_detected')
          .handleUiEvent(
            UserActionEvent(
              surfaceId: 'selling_step_1_detected',
              name: 'confirm_detected_item',
              sourceComponentId: 'btn_confirm',
              context: const <String, Object?>{},
            ),
          );

      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(sellingSessionControllerProvider).isProcessing,
        isTrue,
      );
      expect(fakeAgent.sentActions, hasLength(1));

      // Second duplicate submit while isProcessing is true
      fakeAgent.surfaceController
          .contextFor('selling_step_1_detected')
          .handleUiEvent(
            UserActionEvent(
              surfaceId: 'selling_step_1_detected',
              name: 'confirm_detected_item',
              sourceComponentId: 'btn_confirm',
              context: const <String, Object?>{},
            ),
          );

      await Future<void>.delayed(Duration.zero);
      // Still only 1 sent action because the second was dropped
      expect(fakeAgent.sentActions, hasLength(1));

      // Complete the pending action and emit a surface update
      actionCompleter.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(sellingSessionControllerProvider).status,
        equals(SellingFlowStatus.submittingAction),
      );

      // Agent returns new surface update
      fakeAgent.emitJsonMessages(<Map<String, Object?>>[
        <String, Object?>{
          'version': 'v0.9',
          'updateComponents': <String, Object?>{
            'surfaceId': 'selling_step_1_detected',
            'components': <Map<String, Object?>>[],
          },
        },
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(sellingSessionControllerProvider).isProcessing,
        isFalse,
      );
    });

    test('submittingAction keeps status as submittingAction until agent emits SurfaceUpdate', () async {
      final List<Object?> rawStep1 = jsonDecode(
        File('../contracts/examples/0.9/01_detected_car.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.cannedStartMessages = rawStep1.cast<Map<String, Object?>>();

      final SellingSessionController controller = container.read(
        sellingSessionControllerProvider.notifier,
      );
      await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sellingSessionControllerProvider).status,
        equals(SellingFlowStatus.activeSurface),
      );

      // Trigger submit
      fakeAgent.surfaceController
          .contextFor('selling_step_1_detected')
          .handleUiEvent(
            UserActionEvent(
              surfaceId: 'selling_step_1_detected',
              name: 'confirm_detected_item',
              sourceComponentId: 'btn_confirm',
              context: const <String, Object?>{},
            ),
          );

      await Future<void>.delayed(Duration.zero);

      // Even though sendAction completed immediately, status MUST still be submittingAction
      expect(
        container.read(sellingSessionControllerProvider).status,
        equals(SellingFlowStatus.submittingAction),
      );
      expect(
        container.read(sellingSessionControllerProvider).isProcessing,
        isTrue,
      );

      // Agent returns step 2 surface
      final List<Object?> rawStep2 = jsonDecode(
        File('../contracts/examples/0.9/02_followup_damage_odometer.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.emitJsonMessages(rawStep2.cast<Map<String, Object?>>());
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(sellingSessionControllerProvider).status,
        equals(SellingFlowStatus.activeSurface),
      );
      expect(
        container.read(sellingSessionControllerProvider).activeSurfaceId,
        equals('selling_step_2_followup'),
      );
      expect(
        container.read(sellingSessionControllerProvider).isProcessing,
        isFalse,
      );
    });

    testWidgets(
      'submittingAction falls back to error status if agent does not respond within 25 seconds',
      (WidgetTester tester) async {
        final List<Object?> rawStep1 = jsonDecode(
          File('../contracts/examples/0.9/01_detected_car.json')
              .readAsStringSync(),
        ) as List<Object?>;
        fakeAgent.cannedStartMessages = rawStep1.cast<Map<String, Object?>>();

        final SellingSessionController controller = container.read(
          sellingSessionControllerProvider.notifier,
        );
        await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
        await tester.pump();

        expect(
          container.read(sellingSessionControllerProvider).status,
          equals(SellingFlowStatus.activeSurface),
        );

        fakeAgent.surfaceController
            .contextFor('selling_step_1_detected')
            .handleUiEvent(
              UserActionEvent(
                surfaceId: 'selling_step_1_detected',
                name: 'confirm_detected_item',
                sourceComponentId: 'btn_confirm',
                context: const <String, Object?>{},
              ),
            );

        await tester.pump();
        expect(
          container.read(sellingSessionControllerProvider).status,
          equals(SellingFlowStatus.submittingAction),
        );

        // Advance beyond the 25-second timeout
        await tester.pump(const Duration(seconds: 26));

        expect(
          container.read(sellingSessionControllerProvider).status,
          equals(SellingFlowStatus.error),
        );
        expect(
          container.read(sellingSessionControllerProvider).errorMessage,
          contains('demasiado tiempo'),
        );
      },
    );
  });
}
