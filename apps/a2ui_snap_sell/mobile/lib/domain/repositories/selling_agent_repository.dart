import 'package:genui/genui.dart';

import '../models/captured_photo.dart';

/// Abstract contract for communicating with the remote A2A / A2UI Snap & Sell agent.
abstract interface class SellingAgentRepository {
  /// The active [SurfaceController] hosting A2UI v0.9 surfaces and data models.
  SurfaceController get surfaceController;

  /// Stream of [SurfaceUpdate] events (`SurfaceAdded`, `ComponentsUpdated`, `SurfaceRemoved`).
  Stream<SurfaceUpdate> get surfaceUpdates;

  /// Stream of conversational text snippets from the agent.
  Stream<String> get textStream;

  /// Stream of transport or validation errors.
  Stream<Object> get errorStream;

  /// Starts a new selling session by sending the initial [photo] and [prompt]
  /// as a multimodal A2A message (`TextPart` + binary `DataPart`).
  Future<String?> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  });

  /// Forwards a `SurfaceController.onSubmit` [interactionMessage] to the remote
  /// agent, optionally attaching a binary [followupPhoto] `DataPart`.
  Future<String?> sendAction(
    ChatMessage interactionMessage, {
    CapturedPhoto? followupPhoto,
  });

  /// Cancels any in-flight request and disposes underlying streams/controllers.
  void dispose();
}

/// Alias matching the architecture prompt naming (`A2uiAgentService`).
typedef A2uiAgentService = SellingAgentRepository;
