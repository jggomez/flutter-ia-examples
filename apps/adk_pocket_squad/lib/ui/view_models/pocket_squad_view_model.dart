import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/agents/pocket_squad_agent_factory.dart';
import '../../data/llm/litert_chat_driver.dart';
import '../../data/services/app_storage_service.dart';
import '../../data/services/model_download_service.dart';
import '../../data/services/network_connectivity_service.dart';
import '../../domain/models/budget_breakdown.dart';
import '../../domain/models/llm_engine_config.dart';
import '../../domain/models/saved_trip.dart';
import '../../domain/models/squad_mission_preset.dart';
import '../widgets/flutter_adk_widgets.dart';
import '../widgets/formatted_agent_message_view.dart';

/// Orchestrates the 4-step `CoordinatorAgent` + 3-agent `SequentialAgent`
/// Travel & Budget Concierge workspace, owning the active [AdkChatController],
/// live `session.state` artifacts, [AdkWorkflowStep] timeline, persistent
/// [AdkAgentLogEntry] telemetry stream, and [SavedTrip] vault.
class PocketSquadViewModel extends ChangeNotifier {
  PocketSquadViewModel({
    required this.chatDriver,
    required this.storageService,
    required this.connectivityService,
    required this.downloadService,
    LlmEngineConfig initialEngineConfig = const LlmEngineConfig(),
    bool autoInitialize = true,
  }) : _engineConfig = initialEngineConfig,
       _workflowSteps = _buildInitialSteps() {
    _rebuildBundleAndController();
    if (autoInitialize) {
      unawaited(initialize());
    }
  }

  static const String appName = 'pocket_squad_app';
  static const String defaultUserId = 'concierge_traveler';

  static const List<String> stateArtifactKeys = <String>[
    'itinerary_draft',
    'budget_audit',
    'final_concierge_brief',
  ];

  final LiteRtChatDriver chatDriver;
  final AppStorageService storageService;
  final NetworkConnectivityService connectivityService;
  final ModelDownloadService downloadService;

  late PocketSquadBundle _bundle;
  late AdkChatController _chatController;
  bool _hasController = false;

  LlmEngineConfig _engineConfig;
  bool _isOnWifi = true;
  bool _isBusy = false;
  bool _isDisposed = false;
  int _logSequence = 0;

  List<AdkWorkflowStep> _workflowSteps;
  final List<AdkAgentLogEntry> _agentLogs = <AdkAgentLogEntry>[];
  final Map<String, String> _sessionArtifacts = <String, String>{
    'itinerary_draft': '',
    'budget_audit': '',
    'final_concierge_brief': '',
  };
  BudgetBreakdown? _latestBudget;
  List<SavedTrip> _savedTrips = const <SavedTrip>[];
  List<String> _activeAgentHierarchy = const <String>[
    'coordinator_agent',
    'Ready',
  ];
  String? _activeAgentName;
  String? _statusMessage;

  AdkChatController get chatController => _chatController;
  PocketSquadBundle get bundle => _bundle;
  BaseAgent get pipelineAgent => _bundle.coordinatorAgent;
  List<Object> get registeredTools => _bundle.tools.allTools;
  LlmEngineConfig get engineConfig => _engineConfig;
  bool get isOnWifi => _isOnWifi;
  bool get isBusy => _isBusy || _chatController.isLoading;
  List<AdkWorkflowStep> get workflowSteps =>
      List<AdkWorkflowStep>.unmodifiable(_workflowSteps);
  List<AdkAgentLogEntry> get agentLogs =>
      List<AdkAgentLogEntry>.unmodifiable(_agentLogs);
  List<AdkChatMessage> get toolCallMessages =>
      List<AdkChatMessage>.unmodifiable(
        _chatController.messages.where(
          (m) => m.isTool || m.role == AdkMessageRole.tool,
        ),
      );
  Map<String, String> get sessionArtifacts =>
      Map<String, String>.unmodifiable(_sessionArtifacts);
  BudgetBreakdown? get latestBudget => _latestBudget;
  List<SavedTrip> get savedTrips => List<SavedTrip>.unmodifiable(_savedTrips);
  List<String> get activeAgentHierarchy =>
      List<String>.unmodifiable(_activeAgentHierarchy);
  String? get activeAgentName => _activeAgentName;
  String? get statusMessage => _statusMessage;

  static List<AdkWorkflowStep> _buildInitialSteps() {
    return const <AdkWorkflowStep>[
      AdkWorkflowStep(
        id: 'coordinator_agent',
        label: '0. Coordinator',
        description: 'Conversational Intake · Collects Destination, Days & Budget before handoff',
        status: AdkStepStatus.pending,
      ),
      AdkWorkflowStep(
        id: 'scout_agent',
        label: '1. ScoutAgent',
        description: '100% Native LLM Knowledge · Neighborhoods, day-by-day route & USD estimates',
        status: AdkStepStatus.pending,
      ),
      AdkWorkflowStep(
        id: 'budget_auditor_agent',
        label: '2. BudgetAuditor',
        description: 'FunctionTool(calculate_budget_math) · Exact totals, 10% buffer & FX conversion',
        status: AdkStepStatus.pending,
      ),
      AdkWorkflowStep(
        id: 'concierge_agent',
        label: '3. Concierge',
        description: 'FunctionTool(save_trip_plan) · Executive travel brief & Vault persistence',
        status: AdkStepStatus.pending,
      ),
    ];
  }

  /// Loads persisted trips, engine config, Wi-Fi state, and initializes the
  /// on-device LiteRT-LM driver if needed.
  Future<void> initialize() async {
    try {
      final loadedConfig = await storageService.loadEngineConfig();
      final trips = await storageService.loadSavedTrips();
      final wifi = await connectivityService.isWifiConnected();

      _savedTrips = trips;
      _isOnWifi = wifi;
      if (trips.isNotEmpty && _latestBudget == null) {
        _latestBudget = trips.first.budgetBreakdown;
      }

      if (loadedConfig != _engineConfig) {
        _engineConfig = loadedConfig;
        _rebuildBundleAndController();
      }

      if (_engineConfig.isOnDevice && !chatDriver.isInitialized) {
        final modelPath = await downloadService.findExistingModelPath();
        if (modelPath != null) {
          await chatDriver.initialize(modelFilePath: modelPath);
        }
      }
      _safeNotify();
    } catch (_) {
      _safeNotify();
    }
  }

  void _rebuildBundleAndController() {
    if (_hasController) {
      _chatController.removeListener(_onChatControllerChanged);
      _chatController.dispose();
    }

    _bundle = PocketSquadAgentFactory.create(
      config: _engineConfig,
      driver: chatDriver,
      storageService: storageService,
      onBudgetCalculated: _handleBudgetCalculated,
      onTripSaved: _handleTripSaved,
      onAgentStepUpdate: _handleAgentStepUpdate,
      onTurnEvent: _handleTurnEvent,
    );

    _chatController = AdkChatController(
      agent: _bundle.coordinatorAgent,
      sessionService: _bundle.sessionService,
      appName: appName,
      userId: defaultUserId,
      sessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
    );
    _hasController = true;
    _chatController.addListener(_onChatControllerChanged);
  }

  void _appendLogEntry(AdkAgentLogEntry entry) {
    final existingIndex = _agentLogs.indexWhere((item) => item.id == entry.id);
    if (existingIndex != -1) {
      _agentLogs[existingIndex] = entry;
    } else {
      _agentLogs.add(entry);
    }
  }

  /// Clears all recorded [AdkAgentLogEntry] items from the ADK Studio Live Logger.
  void clearAgentLogs() {
    _agentLogs.clear();
    _safeNotify();
  }

  void _handleTurnEvent(String agentHint, String stage) {
    final seq = ++_logSequence;
    if (stage.startsWith('tool_call:')) {
      final toolName = stage.substring('tool_call:'.length);
      _appendLogEntry(
        AdkAgentLogEntry(
          id: 'turn_tool_${agentHint}_${toolName}_$seq',
          timestamp: DateTime.now(),
          agentName: agentHint,
          category: AdkLogCategory.toolCall,
          title: 'Invoking tool: $toolName',
          subtitle: 'Agent $agentHint dispatching $toolName',
          payload: <String, dynamic>{
            'agent': agentHint,
            'tool': toolName,
            'stage': stage,
          },
        ),
      );
    } else if (stage == 'conversational_intake') {
      _appendLogEntry(
        AdkAgentLogEntry(
          id: 'turn_intake_$seq',
          timestamp: DateTime.now(),
          agentName: agentHint,
          category: AdkLogCategory.modelResponse,
          title: 'Coordinator conversational intake',
          subtitle: 'Collecting Destination, Duration (days), and Total Budget',
          payload: <String, dynamic>{'agent': agentHint, 'stage': stage},
        ),
      );
    } else if (stage == 'generating_narrative') {
      _appendLogEntry(
        AdkAgentLogEntry(
          id: 'turn_gen_${agentHint}_$seq',
          timestamp: DateTime.now(),
          agentName: agentHint,
          category: AdkLogCategory.modelResponse,
          title: 'Generating response ($agentHint)',
          subtitle: 'Running LLM inference for $agentHint',
          payload: <String, dynamic>{'agent': agentHint, 'stage': stage},
        ),
      );
    }
    _safeNotify();
  }

  void _handleBudgetCalculated(BudgetBreakdown breakdown) {
    _latestBudget = breakdown;
    _markStepStatus('coordinator_agent', AdkStepStatus.completed);
    _markStepStatus('scout_agent', AdkStepStatus.completed);
    _markStepStatus('budget_auditor_agent', AdkStepStatus.running);
    _activeAgentName = 'budget_auditor_agent';
    _activeAgentHierarchy = const <String>[
      'coordinator_agent',
      'pocket_squad_pipeline',
      'budget_auditor_agent',
      'calculate_budget_math',
    ];
    _appendLogEntry(
      AdkAgentLogEntry(
        id: 'tool_budget_${++_logSequence}',
        timestamp: DateTime.now(),
        agentName: 'budget_auditor_agent',
        category: AdkLogCategory.toolCall,
        title: 'FunctionTool: calculate_budget_math',
        subtitle:
            'Grand Total: \$${breakdown.grandTotalUsd.toStringAsFixed(2)} USD '
            '(${breakdown.convertedGrandTotal.toStringAsFixed(0)} ${breakdown.targetCurrency})',
        payload: breakdown.toJson(),
      ),
    );
    _safeNotify();
  }

  void _handleTripSaved(SavedTrip trip) {
    final updated = List<SavedTrip>.from(_savedTrips);
    updated.removeWhere((item) => item.id == trip.id);
    updated.insert(0, trip);
    _savedTrips = updated;
    _latestBudget = trip.budgetBreakdown;
    _markStepStatus('coordinator_agent', AdkStepStatus.completed);
    _markStepStatus('scout_agent', AdkStepStatus.completed);
    _markStepStatus('budget_auditor_agent', AdkStepStatus.completed);
    _markStepStatus('concierge_agent', AdkStepStatus.running);
    _activeAgentName = 'concierge_agent';
    _activeAgentHierarchy = const <String>[
      'coordinator_agent',
      'pocket_squad_pipeline',
      'concierge_agent',
      'save_trip_plan',
    ];
    _appendLogEntry(
      AdkAgentLogEntry(
        id: 'tool_save_trip_${trip.id}',
        timestamp: DateTime.now(),
        agentName: 'concierge_agent',
        category: AdkLogCategory.toolCall,
        title: 'FunctionTool: save_trip_plan',
        subtitle: 'Saved ${trip.destination} (${trip.days} days) to Vault',
        payload: trip.toJson(),
      ),
    );
    _safeNotify();
  }

  void _handleAgentStepUpdate(String agentName, String status) {
    final normalizedStatus = status.trim().toLowerCase();
    final stepStatus = switch (normalizedStatus) {
      'running' || 'started' || 'active' => AdkStepStatus.running,
      'completed' || 'done' || 'success' => AdkStepStatus.completed,
      'failed' || 'error' => AdkStepStatus.failed,
      _ => AdkStepStatus.running,
    };

    if (agentName == 'coordinator_agent') {
      _markStepStatus('coordinator_agent', stepStatus);
    } else if (agentName == 'scout_agent') {
      _markStepStatus('coordinator_agent', AdkStepStatus.completed);
      _markStepStatus('scout_agent', stepStatus);
    } else if (agentName == 'budget_auditor_agent') {
      _markStepStatus('coordinator_agent', AdkStepStatus.completed);
      _markStepStatus('scout_agent', AdkStepStatus.completed);
      _markStepStatus('budget_auditor_agent', stepStatus);
    } else if (agentName == 'concierge_agent') {
      _markStepStatus('coordinator_agent', AdkStepStatus.completed);
      _markStepStatus('scout_agent', AdkStepStatus.completed);
      _markStepStatus('budget_auditor_agent', AdkStepStatus.completed);
      _markStepStatus('concierge_agent', stepStatus);
    }

    _activeAgentName = agentName;
    _activeAgentHierarchy = agentName == 'coordinator_agent'
        ? const <String>['coordinator_agent', 'Travel Intake']
        : <String>['coordinator_agent', 'pocket_squad_pipeline', agentName];
    _safeNotify();
  }

  void _onChatControllerChanged() {
    final messages = _chatController.messages;
    for (final msg in messages) {
      final author = msg.author.trim();
      if (msg.isUser) {
        _appendLogEntry(
          AdkAgentLogEntry(
            id: 'msg_${msg.id}',
            timestamp: msg.timestamp,
            agentName: 'user',
            category: AdkLogCategory.userInput,
            title: 'User Prompt',
            subtitle: msg.text,
            payload: <String, dynamic>{'text': msg.text},
          ),
        );
        continue;
      }

      if (msg.isTool || msg.role == AdkMessageRole.tool) {
        final toolTitle = msg.toolResult != null
            ? 'Tool Result: ${msg.toolName ?? "tool"}'
            : 'Tool Call: ${msg.toolName ?? "tool"}';
        final toolSub = msg.toolArgs != null
            ? jsonEncode(msg.toolArgs)
            : (msg.toolResult != null ? jsonEncode(msg.toolResult) : msg.text);
        _appendLogEntry(
          AdkAgentLogEntry(
            id: 'msg_${msg.id}',
            timestamp: msg.timestamp,
            agentName: author.isNotEmpty ? author : 'tool',
            category: AdkLogCategory.toolCall,
            title: toolTitle,
            subtitle: toolSub,
            payload: <String, dynamic>{
              'toolName': msg.toolName,
              if (msg.toolArgs != null) 'args': msg.toolArgs,
              if (msg.toolResult != null) 'result': msg.toolResult,
            },
          ),
        );
        continue;
      }

      final sections = FormattedAgentMessageView.splitAgentSections(
        msg.text,
        fallbackAuthor: author,
      );

      for (var i = 0; i < sections.length; i++) {
        final section = sections[i];
        final sectionAuthor = section.author;
        final isLastSection = i == sections.length - 1;
        final sectionStatus = (msg.isPartial && isLastSection)
            ? AdkStepStatus.running
            : AdkStepStatus.completed;

        _appendLogEntry(
          AdkAgentLogEntry(
            id: 'msg_${msg.id}_${sectionAuthor}_$i',
            timestamp: msg.timestamp,
            agentName: sectionAuthor,
            category: AdkLogCategory.modelResponse,
            title: 'Response from $sectionAuthor',
            subtitle: FormattedAgentMessageView.toPlainPreview(section.content),
            payload: <String, dynamic>{
              'agent': sectionAuthor,
              'text': section.content,
            },
          ),
        );

        if (sectionAuthor == 'coordinator_agent') {
          _activeAgentName = 'coordinator_agent';
          _activeAgentHierarchy = const <String>[
            'coordinator_agent',
            'Travel Intake',
          ];
          _markStepStatus(
            'coordinator_agent',
            sectionStatus,
            output: section.content,
          );
        } else if (sectionAuthor == 'scout_agent') {
          _markStepStatus('coordinator_agent', AdkStepStatus.completed);
          _activeAgentName = 'scout_agent';
          _activeAgentHierarchy = const <String>[
            'coordinator_agent',
            'pocket_squad_pipeline',
            'scout_agent',
          ];
          _sessionArtifacts['itinerary_draft'] = section.content;
          _markStepStatus(
            'scout_agent',
            sectionStatus,
            output: section.content,
          );
        } else if (sectionAuthor == 'budget_auditor_agent') {
          _markStepStatus('coordinator_agent', AdkStepStatus.completed);
          _markStepStatus('scout_agent', AdkStepStatus.completed);
          _activeAgentName = 'budget_auditor_agent';
          _activeAgentHierarchy = const <String>[
            'coordinator_agent',
            'pocket_squad_pipeline',
            'budget_auditor_agent',
          ];
          _sessionArtifacts['budget_audit'] = section.content;
          _markStepStatus(
            'budget_auditor_agent',
            sectionStatus,
            output: section.content,
          );
        } else if (sectionAuthor == 'concierge_agent') {
          _markStepStatus('coordinator_agent', AdkStepStatus.completed);
          _markStepStatus('scout_agent', AdkStepStatus.completed);
          _markStepStatus('budget_auditor_agent', AdkStepStatus.completed);
          _activeAgentName = 'concierge_agent';
          _activeAgentHierarchy = const <String>[
            'coordinator_agent',
            'pocket_squad_pipeline',
            'concierge_agent',
          ];
          _sessionArtifacts['final_concierge_brief'] = section.content;
          _markStepStatus(
            'concierge_agent',
            sectionStatus,
            output: section.content,
          );
        }
      }
    }
    _safeNotify();
  }

  void _markStepStatus(String stepId, AdkStepStatus status, {dynamic output}) {
    _workflowSteps = _workflowSteps.map((step) {
      if (step.id != stepId) return step;
      return step.copyWith(
        status: status,
        output: output ?? step.output,
        startTime: step.startTime ?? DateTime.now(),
        endTime: status == AdkStepStatus.completed
            ? DateTime.now()
            : step.endTime,
      );
    }).toList();
  }

  /// Launches a curated [SquadMissionPreset] through the Coordinator and 3-agent pipeline.
  Future<void> runPresetMission(SquadMissionPreset preset) {
    return runMissionPrompt(preset.prompt);
  }

  /// Sends [prompt] to `coordinator_agent` via [chatController].
  ///
  /// - If `coordinator_agent` replies conversationally (Travel Intake), only
  ///   `coordinator_agent` is marked completed while the 3 specialist agents
  ///   remain `pending`.
  /// - If `coordinator_agent` transfers to `pocket_squad_pipeline`, all 4
  ///   steps complete, `session.state` artifacts sync, and the Vault refreshes.
  Future<void> runMissionPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || isBusy) return;

    _isBusy = true;
    _statusMessage = 'Coordinator analyzing request...';
    final messageCountBefore = _chatController.messages.length;
    _workflowSteps = _buildInitialSteps().map((step) {
      if (step.id == 'coordinator_agent') {
        return step.copyWith(
          status: AdkStepStatus.running,
          startTime: DateTime.now(),
        );
      }
      return step;
    }).toList();
    _activeAgentName = 'coordinator_agent';
    _activeAgentHierarchy = const <String>[
      'coordinator_agent',
      'Travel Intake',
    ];
    _safeNotify();

    try {
      await _chatController.sendMessage(trimmed);

      final newMessages = _chatController.messages
          .skip(messageCountBefore)
          .toList();
      final onlyCoordinatorReplied =
          newMessages.isNotEmpty &&
          newMessages.every(
            (m) =>
                m.isUser ||
                (m.author == 'coordinator_agent' && !m.isTool) ||
                (m.text.contains('CoordinatorAgent') &&
                    !m.text.contains('ConciergeAgent') &&
                    !m.isTool),
          );

      await syncSessionState(markSpecialistSteps: !onlyCoordinatorReplied);
      await refreshSavedTrips();
      await _enrichLatestSavedTripWithFinalResult();

      final hasError = _chatController.currentError != null;
      _markStepStatus('coordinator_agent', AdkStepStatus.completed);

      final pipelineRan =
          !onlyCoordinatorReplied &&
          (_workflowSteps.any(
                (s) =>
                    s.id != 'coordinator_agent' &&
                    s.status != AdkStepStatus.pending,
              ) ||
              (_sessionArtifacts['final_concierge_brief'] ?? '').isNotEmpty);

      if (hasError) {
        _statusMessage = 'Pipeline finished with a warning';
      } else if (pipelineRan) {
        _markStepStatus('scout_agent', AdkStepStatus.completed);
        _markStepStatus('budget_auditor_agent', AdkStepStatus.completed);
        _markStepStatus('concierge_agent', AdkStepStatus.completed);
        _activeAgentName = null;
        _activeAgentHierarchy = const <String>[
          'coordinator_agent',
          'pocket_squad_pipeline',
          'Mission Complete',
        ];
        _statusMessage = 'Mission complete · Trip saved to Vault';
      } else {
        _activeAgentName = 'coordinator_agent';
        _activeAgentHierarchy = const <String>[
          'coordinator_agent',
          'Awaiting Trip Details',
        ];
        _statusMessage = 'Coordinator waiting for Destination, Days & Budget';
      }
    } finally {
      _isBusy = false;
      _safeNotify();
    }
  }

  static String _producerForStateKey(String key) {
    return switch (key) {
      'itinerary_draft' => 'scout_agent',
      'budget_audit' => 'budget_auditor_agent',
      'final_concierge_brief' => 'concierge_agent',
      _ => 'pocket_squad_pipeline',
    };
  }

  /// Synchronizes `itinerary_draft`, `budget_audit`, and `final_concierge_brief`
  /// from the active ADK `Session.state` and records state delta logs.
  Future<void> syncSessionState({bool markSpecialistSteps = true}) async {
    final session = await _chatController.sessionService.getSession(
      appName: _chatController.appName,
      userId: _chatController.userId,
      sessionId: _chatController.sessionId,
    );

    if (session != null) {
      for (final key in stateArtifactKeys) {
        final value = session.state[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          final rawStr = value.toString().trim();
          final cleanedVal = FormattedAgentMessageView.cleanRawAgentHeaders(
            rawStr,
          );
          final strVal = cleanedVal.isNotEmpty ? cleanedVal : rawStr;
          _sessionArtifacts[key] = strVal;
          _appendLogEntry(
            AdkAgentLogEntry(
              id: 'state_${_chatController.sessionId}_$key',
              timestamp: DateTime.now(),
              agentName: _producerForStateKey(key),
              category: AdkLogCategory.stateUpdate,
              title: 'session.state[$key] updated',
              subtitle: FormattedAgentMessageView.toPlainPreview(strVal),
              payload: <String, dynamic>{key: strVal},
            ),
          );
        }
      }
    }

    if (markSpecialistSteps) {
      if ((_sessionArtifacts['itinerary_draft'] ?? '').isNotEmpty) {
        _markStepStatus('coordinator_agent', AdkStepStatus.completed);
        _markStepStatus(
          'scout_agent',
          AdkStepStatus.completed,
          output: _sessionArtifacts['itinerary_draft'],
        );
      }
      if ((_sessionArtifacts['budget_audit'] ?? '').isNotEmpty) {
        _markStepStatus('coordinator_agent', AdkStepStatus.completed);
        _markStepStatus(
          'budget_auditor_agent',
          AdkStepStatus.completed,
          output: _sessionArtifacts['budget_audit'],
        );
      }
      if ((_sessionArtifacts['final_concierge_brief'] ?? '').isNotEmpty) {
        _markStepStatus('coordinator_agent', AdkStepStatus.completed);
        _markStepStatus(
          'concierge_agent',
          AdkStepStatus.completed,
          output: _sessionArtifacts['final_concierge_brief'],
        );
      }
    }
    _safeNotify();
  }

  Future<void> _enrichLatestSavedTripWithFinalResult() async {
    if (_savedTrips.isEmpty) return;

    final cleanedItinerary = FormattedAgentMessageView.cleanRawAgentHeaders(
      _sessionArtifacts['itinerary_draft'] ?? '',
    );
    final cleanedBrief = FormattedAgentMessageView.cleanRawAgentHeaders(
      _sessionArtifacts['final_concierge_brief'] ?? '',
    );

    if (cleanedItinerary.isEmpty && cleanedBrief.isEmpty) return;

    final latest = _savedTrips.first;
    final nextItinerary = cleanedItinerary.isNotEmpty
        ? cleanedItinerary
        : latest.itinerarySummary;
    final nextConcierge = cleanedBrief.isNotEmpty
        ? cleanedBrief
        : latest.conciergeNotes;

    if (nextItinerary == latest.itinerarySummary &&
        nextConcierge == latest.conciergeNotes) {
      return;
    }

    final enriched = latest.copyWith(
      itinerarySummary: nextItinerary,
      conciergeNotes: nextConcierge,
    );
    _savedTrips = await storageService.saveTrip(enriched);
  }

  /// Reloads all persisted [SavedTrip] dossiers from [AppStorageService].
  Future<void> refreshSavedTrips() async {
    _savedTrips = await storageService.loadSavedTrips();
    if (_savedTrips.isNotEmpty && _latestBudget == null) {
      _latestBudget = _savedTrips.first.budgetBreakdown;
    }
    _safeNotify();
  }

  /// Deletes a [SavedTrip] by [tripId] from the Vault.
  Future<void> deleteSavedTrip(String tripId) async {
    _savedTrips = await storageService.deleteTrip(tripId);
    _safeNotify();
  }

  /// Refreshes the native Wi-Fi status indicator via `MethodChannel`.
  Future<void> refreshWifiStatus() async {
    _isOnWifi = await connectivityService.isWifiConnected();
    _safeNotify();
  }

  /// Updates the active [LlmEngineConfig] (On-Device LiteRT-LM vs. LAN Ollama)
  /// and rebuilds the ADK bundle and controller.
  Future<void> updateEngineConfig(LlmEngineConfig newConfig) async {
    if (_engineConfig == newConfig) return;
    _engineConfig = newConfig;
    await storageService.saveEngineConfig(newConfig);
    _isOnWifi = await connectivityService.isWifiConnected();
    _rebuildBundleAndController();
    _workflowSteps = _buildInitialSteps();
    _activeAgentName = null;
    _activeAgentHierarchy = const <String>['coordinator_agent', 'Ready'];
    _statusMessage = 'Switched engine to ${newConfig.engineLabel}';
    _safeNotify();
  }

  /// Rebuilds the bundle/session and resets the 4-step pipeline for a fresh conversation.
  void resetMissionSession() {
    _rebuildBundleAndController();
    _workflowSteps = _buildInitialSteps();
    for (final key in stateArtifactKeys) {
      _sessionArtifacts[key] = '';
    }
    _activeAgentName = null;
    _activeAgentHierarchy = const <String>['coordinator_agent', 'Ready'];
    _statusMessage = null;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_hasController) {
      _chatController.removeListener(_onChatControllerChanged);
      _chatController.dispose();
    }
    super.dispose();
  }
}
