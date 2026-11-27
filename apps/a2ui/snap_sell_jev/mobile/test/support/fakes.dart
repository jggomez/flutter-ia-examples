import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/domain/repositories/image_capture_repository.dart';
import 'package:mobile/domain/repositories/selling_agent_repository.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';

/// Reads the shared contract example [fileName] (`contracts/examples/1.0`).
List<Map<String, Object?>> loadContractExample(String fileName) {
  final File file = File('../contracts/examples/1.0/$fileName');
  return (jsonDecode(file.readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
}

/// A real `a2ui_flutter` renderer with the Snap & Sell catalog that records
/// every renderer-to-agent message.
class A2uiHarness {
  A2uiHarness({CatalogImplementation? catalog}) {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: <CatalogImplementation>[catalog ?? buildSnapSellCatalog()],
      outboundListener: outbound.add,
      unifiedOutbound: true,
      reportErrorsOnly: true,
    );
  }

  late final MessageProcessor<ComponentImplementation> processor;
  final List<RendererToAgentMessage> outbound = <RendererToAgentMessage>[];

  List<ActionMessage> get actions =>
      outbound.whereType<ActionMessage>().toList();
  List<ErrorMessage> get errors => outbound.whereType<ErrorMessage>().toList();
  List<CallAgentFunctionMessage> get agentCalls =>
      outbound.whereType<CallAgentFunctionMessage>().toList();

  void feed(List<Map<String, Object?>> messages) =>
      processor.processMessages(messages);

  SurfaceModel<ComponentImplementation> surface(String id) =>
      processor.model.getSurface(id)!;

  Object? data(String surfaceId, String path) =>
      surface(surfaceId).dataModel.get(path);

  /// Answers the latest `callAgentFunction` with [value].
  void answerLastAgentCall(Object? value) {
    feed(<Map<String, Object?>>[
      <String, Object?>{
        'version': '1.0',
        'agentFunctionResponse': <String, Object?>{
          'functionCallId': agentCalls.last.functionCallId,
          'value': value,
        },
      },
    ]);
  }

  Future<void> pump(WidgetTester tester, String surfaceId) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: A2uiSurface(surface: surface(surfaceId)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() => processor.dispose();
}

/// Builds a one-message v1.0 `createSurface` for the Snap & Sell catalog.
Map<String, Object?> createSurface(
  String surfaceId,
  List<Map<String, Object?>> components, {
  Map<String, Object?>? dataModel,
}) {
  return <String, Object?>{
    'version': '1.0',
    'createSurface': <String, Object?>{
      'surfaceId': surfaceId,
      'catalogId': snapSellCatalogApi.id,
      'components': components,
      'dataModel': ?dataModel,
    },
  };
}

class FakeImageCaptureService implements ImageCaptureRepository {
  /// Pre-configured photo returned by the next [capturePhoto] call.
  CapturedPhoto? nextPhoto = CapturedPhoto(
    bytes: kFakeTransparentPng,
    mimeType: 'image/jpeg',
    fileName: 'test_item.jpg',
    source: PhotoCaptureSource.camera,
  );

  /// Optional exception thrown by [capturePhoto] when non-null.
  Object? nextError;

  /// History of sources passed to [capturePhoto].
  final List<PhotoCaptureSource> capturedSources = <PhotoCaptureSource>[];

  /// Queue of follow-up photos captured by `PhotoRequest` widgets.
  final List<CapturedPhoto> queuedFollowupPhotos = <CapturedPhoto>[];

  /// Last downscaling parameters passed to [capturePhoto].
  double? lastMaxWidth;
  double? lastMaxHeight;
  int? lastImageQuality;

  @override
  Future<CapturedPhoto?> capturePhoto(
    PhotoCaptureSource source, {
    double maxWidth = 1024,
    double maxHeight = 1024,
    int imageQuality = 82,
  }) async {
    capturedSources.add(source);
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastImageQuality = imageQuality;
    if (nextError != null) {
      throw nextError!;
    }
    return nextPhoto;
  }

  @override
  void queueFollowupPhoto(CapturedPhoto photo) {
    queuedFollowupPhotos.add(photo);
  }

  @override
  CapturedPhoto? takeQueuedFollowupPhoto() {
    if (queuedFollowupPhotos.isEmpty) return null;
    return queuedFollowupPhotos.removeAt(0);
  }
}

/// Deterministic in-memory fake for [SellingAgentRepository] / [A2uiAgentService].
/// In-memory [SellingAgentRepository] backed by a real renderer.
class FakeSellingAgentRepository implements SellingAgentRepository {
  FakeSellingAgentRepository({ImageCaptureRepository? imageCaptureService}) {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: <CatalogImplementation>[
        buildSnapSellCatalog(imageCaptureService: imageCaptureService),
      ],
      outboundListener: _onOutbound,
      unifiedOutbound: true,
      reportErrorsOnly: true,
    );
    _subscriptions.addAll(<Subscription>[
      processor.model.onSurfaceCreated.subscribe(
        (SurfaceModel<ComponentImplementation> s) =>
            _surfaceEvents.add(SurfaceCreated(s.id)),
      ),
      processor.model.onSurfaceDeleted.subscribe(
        (String id) => _surfaceEvents.add(SurfaceDeleted(id)),
      ),
    ]);
  }

  late final MessageProcessor<ComponentImplementation> processor;
  final List<Subscription> _subscriptions = <Subscription>[];
  final StreamController<SurfaceEvent> _surfaceEvents =
      StreamController<SurfaceEvent>.broadcast(sync: true);
  final StreamController<SurfaceAction> _actions =
      StreamController<SurfaceAction>.broadcast();
  final StreamController<String> _text = StreamController<String>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<List<JevDecision>> _decisions =
      StreamController<List<JevDecision>>.broadcast(sync: true);

  /// Simulates the agent's Jev trace DataPart for one turn.
  void emitDecisions(List<JevDecision> decisions) => _decisions.add(decisions);

  final List<CapturedPhoto> startedPhotos = <CapturedPhoto>[];
  final List<String> startedPrompts = <String>[];
  final List<SurfaceAction> sentActions = <SurfaceAction>[];
  final List<CapturedPhoto?> sentFollowupPhotos = <CapturedPhoto?>[];
  final List<RendererToAgentMessage> otherOutbound = <RendererToAgentMessage>[];

  List<Map<String, Object?>> cannedStartMessages =
      const <Map<String, Object?>>[];
  List<Map<String, Object?>> cannedActionMessages =
      const <Map<String, Object?>>[];
  Object? nextError;

  /// Replaces the default action handling (for example to never answer).
  Future<void> Function(SurfaceAction action, CapturedPhoto? photo)?
  customSendAction;

  int disposeCount = 0;
  bool _isDisposed = false;

  void _onOutbound(RendererToAgentMessage message) {
    if (_isDisposed) return;
    if (message case ActionMessage(:final A2uiRendererAction action)) {
      _actions.add(
        SurfaceAction(
          name: action.name,
          surfaceId: action.surfaceId,
          context: Map<String, Object?>.from(action.context),
          message: message.toJson(),
        ),
      );
    } else {
      otherOutbound.add(message);
    }
  }

  /// Applies agent messages the way `A2uiAgentService` does.
  void emitJsonMessages(List<Map<String, Object?>> messages) {
    for (final Map<String, Object?> message in messages) {
      final Object? create = message['createSurface'];
      if (create is Map &&
          processor.model.getSurface('${create['surfaceId']}') != null) {
        processor.model.deleteSurface('${create['surfaceId']}');
      }
      processor.processMessages(<Map<String, Object?>>[message]);
    }
  }

  /// Dispatches an agent-bound action from [surfaceId] through the renderer,
  /// as a tapped Button would.
  Future<void> emitUserAction(
    String surfaceId,
    String name, {
    Map<String, Object?> context = const <String, Object?>{},
    String sourceComponentId = 'btn',
  }) {
    return processor.model.getSurface(surfaceId)!.dispatchAction(
      <String, dynamic>{
        'event': <String, Object?>{'name': name, 'context': context},
      },
      sourceComponentId,
    );
  }

  void emitAgentText(String text) {
    if (!_text.isClosed) _text.add(text);
  }

  void emitError(Object error) {
    if (!_errors.isClosed) _errors.add(error);
  }

  @override
  SurfaceModel<ComponentImplementation>? surface(String surfaceId) =>
      processor.model.getSurface(surfaceId);

  @override
  Stream<SurfaceEvent> get surfaceEvents => _surfaceEvents.stream;

  @override
  Stream<SurfaceAction> get actions => _actions.stream;

  @override
  Stream<String> get textStream => _text.stream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Stream<List<JevDecision>> get decisionStream => _decisions.stream;

  @override
  Future<void> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  }) async {
    if (nextError != null) throw nextError!;
    startedPhotos.add(photo);
    startedPrompts.add(prompt);
    if (cannedStartMessages.isNotEmpty) emitJsonMessages(cannedStartMessages);
  }

  @override
  Future<void> sendAction(
    SurfaceAction action, {
    CapturedPhoto? followupPhoto,
  }) async {
    if (nextError != null) throw nextError!;
    sentActions.add(action);
    sentFollowupPhotos.add(followupPhoto);
    if (customSendAction != null) {
      return customSendAction!(action, followupPhoto);
    }
    if (cannedActionMessages.isNotEmpty) emitJsonMessages(cannedActionMessages);
  }

  @override
  void deleteSurface(String surfaceId) =>
      processor.model.deleteSurface(surfaceId);

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    disposeCount++;
    for (final Subscription s in _subscriptions) {
      s.unsubscribe();
    }
    processor.dispose();
    _surfaceEvents.close();
    _actions.close();
    _text.close();
    _errors.close();
    _decisions.close();
  }
}

/// Kept for tests written against the v0.9 fake's name.
typedef FakeA2uiAgentService = FakeSellingAgentRepository;

final Uint8List kFakeTransparentPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
