import 'package:flutter/foundation.dart';

/// A surface appeared or disappeared in the renderer.
sealed class SurfaceEvent {
  const SurfaceEvent(this.surfaceId);

  final String surfaceId;
}

final class SurfaceCreated extends SurfaceEvent {
  const SurfaceCreated(super.surfaceId);
}

final class SurfaceDeleted extends SurfaceEvent {
  const SurfaceDeleted(super.surfaceId);
}

/// An agent-bound user action emitted by a surface (A2UI v1.0 `action`).
@immutable
class SurfaceAction {
  const SurfaceAction({
    required this.name,
    required this.surfaceId,
    required this.message,
    this.context = const <String, Object?>{},
  });

  final String name;
  final String surfaceId;
  final Map<String, Object?> context;

  /// The full renderer-to-agent message, sent as-is to the agent.
  final Map<String, Object?> message;
}
