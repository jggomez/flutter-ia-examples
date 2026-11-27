import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';

import '../models/captured_photo.dart';
import '../models/surface_event.dart';

export '../models/surface_event.dart';

/// The selling agent as the app sees it: A2UI v1.0 surfaces it renders, the
/// user actions they emit, and the turns sent to the agent.
abstract interface class SellingAgentRepository {
  /// The renderer-side model of [surfaceId], or null when it does not exist.
  SurfaceModel<ComponentImplementation>? surface(String surfaceId);

  Stream<SurfaceEvent> get surfaceEvents;

  /// Agent-bound actions emitted by rendered surfaces.
  Stream<SurfaceAction> get actions;

  Stream<String> get textStream;

  Stream<Object> get errorStream;

  /// Sends the first photo; completes when the agent's turn has streamed.
  Future<void> startSession({
    required CapturedPhoto photo,
    String prompt = 'Analyze this item and start the selling wizard.',
  });

  /// Sends [action] (and an optional follow-up photo) as the next turn.
  Future<void> sendAction(SurfaceAction action, {CapturedPhoto? followupPhoto});

  void deleteSurface(String surfaceId);

  void dispose();
}
