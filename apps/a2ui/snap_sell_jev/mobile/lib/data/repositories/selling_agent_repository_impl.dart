import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/repositories/selling_agent_repository.dart';
import '../services/a2a_client.dart';
import '../services/a2ui_agent_service.dart';

class SellingAgentRepositoryImpl implements SellingAgentRepository {
  SellingAgentRepositoryImpl({
    required AppConfig config,
    required CatalogImplementation catalog,
    A2uiAgentService? agentService,
  }) : _service =
           agentService ?? A2uiAgentService(config: config, catalog: catalog);

  final A2uiAgentService _service;

  static A2aFilePart _photoPart(CapturedPhoto photo) => A2aFilePart(
    bytes: photo.bytes,
    mimeType: photo.mimeType,
    name: photo.fileName,
  );

  @override
  SurfaceModel<ComponentImplementation>? surface(String surfaceId) =>
      _service.surface(surfaceId);

  @override
  Stream<SurfaceEvent> get surfaceEvents => _service.surfaceEvents;

  @override
  Stream<SurfaceAction> get actions => _service.actions;

  @override
  Stream<String> get textStream => _service.textStream;

  @override
  Stream<Object> get errorStream => _service.errorStream;

  @override
  Stream<List<JevDecision>> get decisionStream => _service.decisionStream;

  @override
  Future<void> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  }) {
    return _service.sendTurn(<A2aPart>[A2aTextPart(prompt), _photoPart(photo)]);
  }

  @override
  Future<void> sendAction(
    SurfaceAction action, {
    CapturedPhoto? followupPhoto,
  }) {
    return _service.sendTurn(<A2aPart>[
      A2aDataPart.a2ui(action.message),
      if (followupPhoto != null) _photoPart(followupPhoto),
    ]);
  }

  @override
  void deleteSurface(String surfaceId) => _service.deleteSurface(surfaceId);

  @override
  void dispose() => _service.dispose();
}
