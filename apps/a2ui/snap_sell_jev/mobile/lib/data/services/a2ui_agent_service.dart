import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../domain/models/jev_decision.dart';
import '../../domain/models/surface_event.dart';
import 'a2a_client.dart';

/// Bridges the A2A agent and the A2UI v1.0 renderer (`a2ui_flutter`).
///
/// * Agent → renderer: A2UI DataParts go to [MessageProcessor.processMessages].
/// * Renderer → agent: the processor's unified `outboundListener` yields
///   `action`, `error` and `callAgentFunction` messages. Actions are surfaced
///   to the app ([actions]); function calls are answered by the agent without
///   an LLM turn and fed back as `agentFunctionResponse`; render errors go
///   back to the agent once per turn so it can correct the surface.
class A2uiAgentService {
  A2uiAgentService({
    required AppConfig config,
    required CatalogImplementation catalog,
    A2aClient? client,
  }) : _client =
           client ??
           A2aClient(
             endpoint: config.uri,
             headers: <String, String>{
               if (config.token.isNotEmpty)
                 'Authorization': 'Bearer ${config.token}',
             },
           ) {
    processor = MessageProcessor<ComponentImplementation>(
      catalogs: <CatalogImplementation>[catalog],
      outboundListener: _onOutbound,
      unifiedOutbound: true,
      // Errors reach [_onOutbound] as ErrorMessages instead of throwing.
      reportErrorsOnly: true,
      defaultTimeout: const Duration(seconds: 10),
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

  final A2aClient _client;
  late final MessageProcessor<ComponentImplementation> processor;

  final StreamController<SurfaceEvent> _surfaceEvents =
      StreamController<SurfaceEvent>.broadcast();
  final StreamController<SurfaceAction> _actions =
      StreamController<SurfaceAction>.broadcast();
  final StreamController<String> _text = StreamController<String>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<List<JevDecision>> _decisions =
      StreamController<List<JevDecision>>.broadcast();
  final List<Subscription> _subscriptions = <Subscription>[];

  String? _contextId;
  bool _errorReportedThisTurn = false;
  bool _disposed = false;

  Stream<SurfaceEvent> get surfaceEvents => _surfaceEvents.stream;
  Stream<SurfaceAction> get actions => _actions.stream;
  Stream<String> get textStream => _text.stream;
  Stream<Object> get errorStream => _errors.stream;

  /// Jev's decisions for each turn (the trace DataPart the agent sends).
  Stream<List<JevDecision>> get decisionStream => _decisions.stream;

  SurfaceModel<ComponentImplementation>? surface(String id) =>
      processor.model.getSurface(id);

  void deleteSurface(String id) => processor.model.deleteSurface(id);

  /// What this renderer supports, sent with every turn so the agent builds
  /// its Express prompt for exactly these catalogs.
  Map<String, Object?> get rendererCapabilities => processor
      .getRendererCapabilities(
        const CapabilitiesOptions(
          versions: <A2uiProtocolVersion>[A2uiProtocolVersion.v1_0],
        ),
      )
      .toJson();

  /// Runs one agent turn and applies every A2UI message it streams back.
  Future<void> sendTurn(List<A2aPart> parts) async {
    _errorReportedThisTurn = false;
    final Map<String, Object?>? dataModel = processor.getRendererDataModel();
    final Set<String> applied = <String>{};
    await for (final A2aEvent event in _client.sendMessage(
      parts: parts,
      contextId: _contextId,
      metadata: <String, Object?>{
        'a2uiRendererCapabilities': rendererCapabilities,
        'a2uiClientDataModel': ?dataModel,
      },
    )) {
      if (_disposed) return;
      _contextId = event.contextId ?? _contextId;
      if (event.isFailure) {
        final String detail = event.parts
            .whereType<A2aTextPart>()
            .map((A2aTextPart p) => p.text)
            .join(' ');
        _errors.add('Agent task ${event.state}: $detail'.trim());
        continue;
      }
      for (final A2aPart part in event.parts) {
        switch (part) {
          case A2aTextPart(:final String text) when text.trim().isNotEmpty:
            _text.add(text.trim());
          case A2aDataPart(:final Map<String, Object?> data) when part.isA2ui:
            // ADK may repeat the final content in a status and an artifact
            // event; apply each A2UI message once per turn.
            if (applied.add(data.toString())) applyA2uiMessage(data);
          case A2aDataPart(:final Map<String, Object?> data)
              when data.containsKey('jevTrace'):
            if (applied.add(data.toString())) {
              _decisions.add(JevDecision.listFromTrace(data['jevTrace']));
            }
          default:
        }
      }
    }
  }

  /// Applies one agent-to-renderer A2UI v1.0 message.
  @visibleForTesting
  void applyA2uiMessage(Map<String, Object?> message) {
    // v1.0 rejects createSurface for an id that already exists. The agent
    // re-sends a whole stage when the seller goes back, so replace it.
    final Object? create = message['createSurface'];
    if (create is Map && create['surfaceId'] is String) {
      final String id = create['surfaceId'] as String;
      if (processor.model.getSurface(id) != null) deleteSurface(id);
    }
    processor.processMessages(<Map<String, Object?>>[message]);
  }

  Future<void> _onOutbound(RendererToAgentMessage message) async {
    if (_disposed) return;
    switch (message) {
      case ActionMessage(:final A2uiRendererAction action):
        _actions.add(
          SurfaceAction(
            name: action.name,
            surfaceId: action.surfaceId,
            context: Map<String, Object?>.from(action.context),
            message: message.toJson(),
          ),
        );
      case CallAgentFunctionMessage():
        await _callAgentFunction(message);
      case ErrorMessage(:final A2uiRendererError error):
        _errors.add('A2UI ${error.code}: ${error.message}');
        if (_errorReportedThisTurn) return;
        _errorReportedThisTurn = true;
        unawaited(
          sendTurn(<A2aPart>[A2aDataPart.a2ui(message.toJson())])
              .catchError((Object e) => _errors.add(e)),
        );
      default:
        await _sendOneShot(message.toJson());
    }
  }

  /// `callAgentFunction` → `agentFunctionResponse`, outside the LLM session.
  Future<void> _callAgentFunction(CallAgentFunctionMessage message) async {
    try {
      await for (final A2aEvent event in _client.sendMessage(
        parts: <A2aPart>[A2aDataPart.a2ui(message.toJson())],
      )) {
        for (final A2aDataPart part in event.parts.whereType<A2aDataPart>()) {
          if (part.data.containsKey('agentFunctionResponse') && !_disposed) {
            processor.processMessages(<Map<String, Object?>>[part.data]);
          }
        }
      }
    } on Object catch (e) {
      // The pending call times out in a2ui_core and reports EXECUTION_ERROR.
      debugPrint('callAgentFunction ${message.functionCallId} failed: $e');
    }
  }

  Future<void> _sendOneShot(Map<String, Object?> payload) async {
    try {
      await _client
          .sendMessage(parts: <A2aPart>[A2aDataPart.a2ui(payload)])
          .drain<void>();
    } on Object catch (e) {
      _errors.add(e);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final Subscription subscription in _subscriptions) {
      subscription.unsubscribe();
    }
    processor.dispose();
    _client.close();
    _surfaceEvents.close();
    _actions.close();
    _text.close();
    _errors.close();
    _decisions.close();
  }
}
