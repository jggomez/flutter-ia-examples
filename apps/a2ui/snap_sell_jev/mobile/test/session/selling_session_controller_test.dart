import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/models/captured_photo.dart';
import 'package:mobile/domain/models/surface_event.dart';
import 'package:mobile/ui/features/selling/view_models/selling_session_state.dart';
import 'package:mobile/ui/features/selling/view_models/selling_session_view_model.dart';
import 'package:mobile/ui/providers/repository_providers.dart';

import '../support/fakes.dart';

const String _step1 = 'selling_step_1_detected';
const String _step2 = 'selling_step_2_followup';

void main() {
  late FakeImageCaptureService fakeCapture;
  late FakeSellingAgentRepository fakeAgent;
  late ProviderContainer container;

  SellingSessionState state() =>
      container.read(sellingSessionViewModelProvider);
  SellingSessionViewModel viewModel() =>
      container.read(sellingSessionViewModelProvider.notifier);
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    fakeCapture = FakeImageCaptureService();
    fakeAgent = FakeSellingAgentRepository(imageCaptureService: fakeCapture);
    container = ProviderContainer(
      overrides: [
        imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
        sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('starts idle with no active surface', () {
    expect(state().status, SellingFlowStatus.idle);
    expect(state().activeSurfaceId, isNull);
    expect(state().surfaceHistory, isEmpty);
  });

  test(
    'startSessionWithPhoto sends the photo and activates the surface',
    () async {
      fakeAgent.cannedStartMessages = loadContractExample(
        '01_detected_car.json',
      );

      await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
      await flush();

      expect(fakeCapture.capturedSources, <PhotoCaptureSource>[
        PhotoCaptureSource.camera,
      ]);
      expect(fakeAgent.startedPhotos, hasLength(1));
      expect(state().status, SellingFlowStatus.activeSurface);
      expect(state().activeSurfaceId, _step1);
      expect(state().localPhotos.keys, contains('initial'));
    },
  );

  test('cancelled capture returns to idle without calling the agent', () async {
    fakeCapture.nextPhoto = null;
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.gallery);
    expect(state().status, SellingFlowStatus.idle);
    expect(fakeAgent.startedPhotos, isEmpty);
  });

  test('agent failure on start surfaces an error', () async {
    fakeAgent.nextError = Exception('agent down');
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    expect(state().status, SellingFlowStatus.error);
    expect(state().errorMessage, contains('agent down'));
  });

  test('ignores a second start while the first is processing', () async {
    final Future<void> first = viewModel().startSessionWithPhoto(
      PhotoCaptureSource.camera,
    );
    expect(state().isProcessing, isTrue);
    final Future<void> second = viewModel().startSessionWithPhoto(
      PhotoCaptureSource.gallery,
    );
    await Future.wait(<Future<void>>[first, second]);
    expect(fakeCapture.capturedSources, <PhotoCaptureSource>[
      PhotoCaptureSource.camera,
    ]);
    expect(fakeAgent.startedPhotos, hasLength(1));
  });

  test('a surface action is sent with the queued follow-up photo', () async {
    fakeAgent.cannedStartMessages = loadContractExample(
      '02_followup_damage_odometer.json',
    );
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    await flush();
    fakeCapture.queueFollowupPhoto(fakeCapture.nextPhoto!);

    await fakeAgent.emitUserAction(
      _step2,
      'upload_followup_photo',
      context: const <String, Object?>{'target': 'odometer'},
    );
    await flush();

    expect(fakeAgent.sentActions, hasLength(1));
    final SurfaceAction action = fakeAgent.sentActions.single;
    expect(action.name, 'upload_followup_photo');
    expect(action.surfaceId, _step2);
    expect(action.context, <String, Object?>{'target': 'odometer'});
    expect(action.message['version'], '1.0');
    expect(fakeAgent.sentFollowupPhotos.single, isNotNull);
  });

  test(
    'stays submittingAction until the agent creates the next surface',
    () async {
      fakeAgent.cannedStartMessages = loadContractExample(
        '01_detected_car.json',
      );
      await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
      await flush();
      final Completer<void> reply = Completer<void>();
      fakeAgent.customSendAction = (SurfaceAction a, CapturedPhoto? p) =>
          reply.future;

      await fakeAgent.emitUserAction(_step1, 'submit_detected_details');
      await flush();
      expect(state().status, SellingFlowStatus.submittingAction);

      // A double tap while processing is ignored.
      await fakeAgent.emitUserAction(_step1, 'submit_detected_details');
      await flush();
      expect(fakeAgent.sentActions, hasLength(1));

      fakeAgent.emitJsonMessages(
        loadContractExample('02_followup_damage_odometer.json'),
      );
      reply.complete();
      await flush();
      expect(state().status, SellingFlowStatus.activeSurface);
      expect(state().activeSurfaceId, _step2);
      expect(state().surfaceHistory, <String>[_step1, _step2]);
    },
  );

  test('a re-sent stage replaces its surface and stays active', () async {
    fakeAgent.cannedStartMessages = loadContractExample('01_detected_car.json');
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    await flush();
    fakeAgent.emitJsonMessages(loadContractExample('01_detected_car.json'));
    await flush();
    expect(state().activeSurfaceId, _step1);
    expect(state().surfaceHistory, <String>[_step1]);
  });

  test('restart_flow resets the session without calling the agent', () async {
    fakeAgent.cannedStartMessages = loadContractExample(
      '05_unsupported_item.json',
    );
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    await flush();

    await fakeAgent.emitUserAction('selling_unsupported', 'restart_flow');
    await flush();

    expect(fakeAgent.sentActions, isEmpty);
    expect(state().status, SellingFlowStatus.idle);
    expect(fakeAgent.surface('selling_unsupported'), isNull);
  });

  test('publish_listing marks the listing as published', () async {
    fakeAgent.cannedStartMessages = loadContractExample(
      '04_listing_preview.json',
    );
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    await flush();

    await fakeAgent.emitUserAction('selling_step_3_preview', 'publish_listing');
    await flush();
    expect(state().status, SellingFlowStatus.published);
  });

  test('agent text and errors reach the state', () async {
    viewModel(); // subscribes to the repository streams
    fakeAgent.emitAgentText('  Looking at your car...  ');
    await flush();
    expect(state().lastAgentText, 'Looking at your car...');

    fakeAgent.emitError('A2UI UNALLOWED_PARENT: bad');
    await flush();
    expect(state().status, SellingFlowStatus.error);
    viewModel().clearError();
    expect(state().errorMessage, isNull);
  });

  testWidgets('submittingAction times out after 25 s', (
    WidgetTester tester,
  ) async {
    fakeAgent.cannedStartMessages = loadContractExample('01_detected_car.json');
    await viewModel().startSessionWithPhoto(PhotoCaptureSource.camera);
    await tester.pump();
    fakeAgent.customSendAction = (SurfaceAction a, CapturedPhoto? p) async {};

    await fakeAgent.emitUserAction(_step1, 'submit_detected_details');
    await tester.pump();
    expect(state().status, SellingFlowStatus.submittingAction);

    await tester.pump(const Duration(seconds: 26));
    expect(state().status, SellingFlowStatus.error);
    expect(state().errorMessage, contains('demasiado tiempo'));
  });
}
