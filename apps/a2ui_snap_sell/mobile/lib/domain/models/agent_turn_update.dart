import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

/// Immutable domain event emitted by the selling agent repository.
@immutable
class AgentTurnUpdate {
  /// Creates an [AgentTurnUpdate].
  const AgentTurnUpdate({
    this.surfaceUpdate,
    this.agentText,
    this.errorMessage,
    this.isProcessing = false,
  });

  /// Optional surface lifecycle update (`SurfaceAdded`, `ComponentsUpdated`, `SurfaceRemoved`).
  final SurfaceUpdate? surfaceUpdate;

  /// Optional conversational text from the agent.
  final String? agentText;

  /// Optional error message if transport or validation failed.
  final String? errorMessage;

  /// Whether the agent transport is currently processing a turn.
  final bool isProcessing;
}
