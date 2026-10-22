import 'package:genui/genui.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/captured_photo.dart';
import '../../domain/repositories/selling_agent_repository.dart';
import '../services/genui_agent_service.dart';

/// Production implementation of [SellingAgentRepository] backed by [GenUiAgentService].
class SellingAgentRepositoryImpl implements SellingAgentRepository {
  /// Creates a [SellingAgentRepositoryImpl].
  SellingAgentRepositoryImpl({
    required AppConfig config,
    required Catalog catalog,
    GenUiAgentService? agentService,
  }) : _service =
           agentService ??
           GenUiAgentService(
             config: config,
             surfaceController: SurfaceController(catalogs: <Catalog>[catalog]),
           );

  final GenUiAgentService _service;

  @override
  SurfaceController get surfaceController => _service.surfaceController;

  @override
  Stream<SurfaceUpdate> get surfaceUpdates =>
      _service.surfaceController.surfaceUpdates;

  @override
  Stream<String> get textStream => _service.textStream;

  @override
  Stream<Object> get errorStream => _service.errorStream;

  @override
  Future<String?> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  }) async {
    final ChatMessage message = ChatMessage.user(
      prompt,
      parts: <StandardPart>[
        DataPart(photo.bytes, mimeType: photo.mimeType, name: photo.fileName),
      ],
    );
    await _service.sendMessage(message);
    return null;
  }

  @override
  Future<String?> sendAction(
    ChatMessage interactionMessage, {
    CapturedPhoto? followupPhoto,
  }) async {
    final ChatMessage outbound = followupPhoto == null
        ? interactionMessage
        : ChatMessage(
            role: interactionMessage.role,
            parts: <StandardPart>[
              ...interactionMessage.parts,
              DataPart(
                followupPhoto.bytes,
                mimeType: followupPhoto.mimeType,
                name: followupPhoto.fileName,
              ),
            ],
          );
    await _service.sendMessage(outbound);
    return null;
  }

  @override
  void dispose() {
    _service.dispose();
  }
}
