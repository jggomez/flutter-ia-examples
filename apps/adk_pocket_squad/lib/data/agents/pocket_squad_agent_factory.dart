import 'package:adk_dart/adk_core.dart';

import '../../domain/models/budget_breakdown.dart';
import '../../domain/models/llm_engine_config.dart';
import '../../domain/models/saved_trip.dart';
import '../llm/litert_chat_driver.dart';
import '../llm/on_device_litert_gemma_llm.dart';
import '../services/app_storage_service.dart';
import 'pocket_squad_tools.dart';

/// Immutable bundle containing the root conversational `CoordinatorAgent`,
/// the 3-agent `SequentialAgent` pipeline, individual specialist agents,
/// authentic `FunctionTool` registry, and active `BaseLlm` instance.
class PocketSquadBundle {
  PocketSquadBundle({
    required this.coordinatorAgent,
    required this.pipelineAgent,
    required this.scoutAgent,
    required this.budgetAuditorAgent,
    required this.conciergeAgent,
    required this.tools,
    required this.llm,
    InMemorySessionService? sessionService,
  }) : sessionService = sessionService ?? InMemorySessionService();

  final LlmAgent coordinatorAgent;
  final SequentialAgent pipelineAgent;
  final LlmAgent scoutAgent;
  final LlmAgent budgetAuditorAgent;
  final LlmAgent conciergeAgent;
  final PocketSquadTools tools;
  final BaseLlm llm;
  final InMemorySessionService sessionService;

  /// Root conversational entry point (`coordinator_agent`) that greets the user,
  /// collects Destination + Duration + Budget across turns, and delegates to
  /// [pipelineAgent] via ADK `AutoFlow` (`transfer_to_agent`).
  BaseAgent get rootAgent => coordinatorAgent;
}

/// Factory assembling the root conversational `CoordinatorAgent` and the
/// 3-agent `SequentialAgent` Travel & Budget Concierge pipeline
/// (`scout_agent` → `budget_auditor_agent` → `concierge_agent`).
class PocketSquadAgentFactory {
  const PocketSquadAgentFactory._();

  static const String coordinatorAgentName = 'coordinator_agent';
  static const String pipelineAgentName = 'pocket_squad_pipeline';
  static const String scoutAgentName = 'scout_agent';
  static const String budgetAuditorAgentName = 'budget_auditor_agent';
  static const String conciergeAgentName = 'concierge_agent';

  /// Creates a configured [PocketSquadBundle] bound to either the shared
  /// on-device [OnDeviceLiteRtGemmaLlm] (`gemma-4-E2B-it.litertlm`) or
  /// a LAN Ollama [LiteLlm] endpoint.
  static PocketSquadBundle create({
    required LlmEngineConfig config,
    required LiteRtChatDriver driver,
    required AppStorageService storageService,
    InMemorySessionService? sessionService,
    void Function(String agentName, String status)? onAgentStepUpdate,
    void Function(BudgetBreakdown breakdown)? onBudgetCalculated,
    void Function(SavedTrip trip)? onTripSaved,
    void Function(String agentHint, String stage)? onTurnEvent,
  }) {
    final tools = PocketSquadTools(
      storageService: storageService,
      engineLabelProvider: () => config.engineLabel,
      onBudgetCalculated: onBudgetCalculated,
      onTripSaved: onTripSaved,
    );

    final BaseLlm llm = switch (config.mode) {
      LlmEngineMode.onDeviceLiteRt => OnDeviceLiteRtGemmaLlm(
        driver: driver,
        model: config.onDeviceModelName,
        onTurnEvent: onTurnEvent,
      ),
      LlmEngineMode.lanOllama => LiteLlm(
        model: config.ollamaModel,
        baseUrl: config.ollamaBaseUrl,
      ),
    };

    final scoutAgent = LlmAgent(
      name: scoutAgentName,
      description:
          'Destination & Route Specialist using 100% native LLM world knowledge '
          'to design neighborhoods and a complete Day-by-Day itinerary '
          '(Morning, Afternoon, Evening) with specific landmarks and local spots.',
      model: llm,
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
      outputKey: 'itinerary_draft',
      instruction: '''
You are `scout_agent`, the Destination & Route Specialist of Pocket Squad.
Use your own world knowledge (0 tools) to design a complete, authentic Day-by-Day travel itinerary in the user's language (Spanish or English).
- Start immediately with Day 1 (`### Día 1: [Zona/Barrio]` or `### Day 1: [Neighborhood]`).
- For every single day of the trip, include specific named landmarks, neighborhoods, streets, and culinary areas for:
  - **Mañana / Morning**
  - **Tarde / Afternoon**
  - **Noche / Evening**
- Do NOT write budget tables or currency breakdowns (the Financial Auditor handles all budget math).''',
      beforeAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(scoutAgentName, 'running');
        return null;
      },
      afterAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(scoutAgentName, 'completed');
        return null;
      },
    );

    final budgetAuditorAgent = LlmAgent(
      name: budgetAuditorAgentName,
      description:
          'Financial Auditor that invokes `calculate_budget_math` to compute '
          'exact multi-day totals, 10% contingency buffers, and currency conversions.',
      model: llm,
      tools: <Object>[tools.calculateBudgetMathTool],
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
      outputKey: 'budget_audit',
      instruction: '''
You are `budget_auditor_agent`, the Financial Auditor of Pocket Squad.
Review the draft itinerary in {itinerary_draft}.
1. Call the `calculate_budget_math` tool with `days`, `lodging_per_night_usd`, `food_per_day_usd`, `activities_total_usd`, `target_currency`, and `user_budget_usd`.
2. Summarize the audited USD breakdown, 10% contingency buffer, converted target currency total, and whether the trip is WITHIN BUDGET or OVER BUDGET in the user's language (Spanish or English) using clean bullet points (no markdown pipe tables).''',
      beforeAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(budgetAuditorAgentName, 'running');
        return null;
      },
      afterAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(budgetAuditorAgentName, 'completed');
        return null;
      },
    );

    final conciergeAgent = LlmAgent(
      name: conciergeAgentName,
      description:
          'Chief Travel Concierge that calls `save_trip_plan` to persist the '
          'audited trip into the Saved Trips Vault and delivers local gastronomy, '
          'insider logistics, and packing checklist.',
      model: llm,
      tools: <Object>[tools.saveTripPlanTool],
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
      outputKey: 'final_concierge_brief',
      instruction: '''
You are `concierge_agent`, the Chief Travel Concierge of Pocket Squad.
Review the route in {itinerary_draft} and financial audit in {budget_audit}.
1. Call `save_trip_plan` to persist the finalized trip dossier and packing checklist into the local Saved Trips Vault.
2. Provide a concise Luxury Concierge Guide in the user's language (Spanish or English) with:
   - **Gastronomía y Platos Típicos / Must-Try Local Dishes & Spots** (3 specific local dishes and where to try them)
   - **Consejos Locales y Logística / Insider Logistics & Best Hours** (3 practical transport, schedule, and reservation tips)
   - **Lista de Equipaje / Essential Packing Checklist** (4 tailored items)
Do NOT repeat the budget table or financial numbers.''',
      beforeAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(conciergeAgentName, 'running');
        return null;
      },
      afterAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(conciergeAgentName, 'completed');
        return null;
      },
    );

    final pipelineAgent = SequentialAgent(
      name: pipelineAgentName,
      description:
          'Sequential 3-agent travel & budget concierge pipeline '
          '(ScoutAgent -> BudgetAuditorAgent -> ConciergeAgent).',
      subAgents: <BaseAgent>[scoutAgent, budgetAuditorAgent, conciergeAgent],
    );

    final coordinatorAgent = LlmAgent(
      name: coordinatorAgentName,
      description:
          'Conversational Travel Concierge Coordinator that greets the user, '
          'collects Destination, Duration (days), and Budget across turns, and '
          'delegates to pocket_squad_pipeline via transfer_to_agent once ready.',
      model: llm,
      subAgents: <BaseAgent>[pipelineAgent],
      instruction: '''
You are `coordinator_agent`, the friendly Receptionist & Travel Coordinator of Pocket Squad.
Your role is to converse naturally with the user in their language (Spanish or English) and gather the 3 required trip details before launching the specialist squad:
1. Destination (city or country)
2. Duration (number of days or nights)
3. Total Budget (amount in USD or local currency)

- If the user greets you ("Hola", "Hi", "Buenos días", etc.) or has not yet provided all 3 details, reply warmly and ask only for the missing details. Do NOT invent or assume default destinations, days, or budgets.
- Once all 3 details (Destination, Duration, and Budget) have been provided across the conversation, immediately call `transfer_to_agent(agent_name: 'pocket_squad_pipeline')` to delegate to the 3-agent specialist pipeline (`scout_agent` -> `budget_auditor_agent` -> `concierge_agent`).''',
      beforeAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(coordinatorAgentName, 'running');
        return null;
      },
      afterAgentCallback: (CallbackContext context) {
        onAgentStepUpdate?.call(coordinatorAgentName, 'completed');
        return null;
      },
    );

    return PocketSquadBundle(
      coordinatorAgent: coordinatorAgent,
      pipelineAgent: pipelineAgent,
      scoutAgent: scoutAgent,
      budgetAuditorAgent: budgetAuditorAgent,
      conciergeAgent: conciergeAgent,
      tools: tools,
      llm: llm,
      sessionService: sessionService,
    );
  }
}
