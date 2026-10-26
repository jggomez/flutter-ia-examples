# ADR 0001: 100% On-Device ADK + LiteRT-LM Multi-Agent Architecture & Authentic Tool Boundary

- **Status**: Accepted
- **Date**: 2026-10-25
- **Scope**: `apps/adk_pocket_squad` (`lib/domain/`, `lib/data/llm/`, `lib/data/agents/`, `lib/data/repositories/`)

## Context & Problem Statement

We need to architect **Pocket Squad** (`apps/adk_pocket_squad`), an on-device Multi-Agent Travel & Budget Concierge running on Android (`OPPO Reno10 5G` / `CPH2531` and general arm64 Android devices) using `flutter_adk` (`^2026.10.23` / `package:adk_dart/adk_core.dart`).

Key architectural challenges:
1. **100% On-Device Standalone Execution + Optional LAN Mode**: `flutter_adk` provides `BaseLlm` and `LiteLlm` (for OpenAI-compatible HTTP endpoints like Ollama / LM Studio), while `flutter_edge_ai` (`^0.1.3`) + `flutter_edge_ai_litertlm` (`^0.1.3+1`) provides Dart FFI bindings to Google's LiteRT-LM engine (`gemma-4-E2B-it.litertlm`, `2.58 GB`, `ModelType.gemma4`, `PreferredBackend.cpu`, `mmap` ~0.8 GB RAM). Loading multiple instances of a 2.58 GB model across 3 sub-agents would exhaust mobile RAM.
2. **Authentic LLM vs. `FunctionTool` Boundary**: Small on-device models (`Gemma 4 E2B IT`) possess broad world knowledge of cities, neighborhoods, and travel routes, yet struggle with exact multi-day arithmetic, currency conversion, and persistent device storage. Conversely, hardcoding a toy dictionary of cities/POIs inside a fake tool defeats the purpose of an LLM.
3. **Structured Tool Calling on Edge Models**: On-device LiteRT-LM models emit text completions rather than native cloud-API tool-call protobuf frames unless bridged via a deterministic JSON tool-call protocol and parser inside `BaseLlm.generateContent()`.

## Decision

### 1. Dual-Mode `BaseLlm` Strategy & Shared Singleton `LiteRtChatDriver`
- **`LiteRtChatDriver` (`lib/data/llm/litert_chat_driver.dart`)**:
  - Wraps `flutter_edge_ai` (`EdgeAi` / LiteRT-LM runtime) as a **single shared singleton instance** in memory (`ModelType.gemma4`, `PreferredBackend.cpu`, `maxTokens: 2048`).
  - Exposes serialized turn execution so all 3 agents in the `SequentialAgent` pipeline reuse the same `mmap`-backed 2.58 GB model in RAM (~0.8 GB resident working set) by resetting conversation context per agent turn without reloading model weights.
- **`OnDeviceLiteRtGemmaLlm extends BaseLlm` (`lib/data/llm/on_device_litert_gemma_llm.dart`)**:
  - Implements `package:adk_dart/adk_core.dart`'s `BaseLlm` contract (`Stream<LlmResponse> generateContent(LlmRequest request, {bool stream = false})`).
  - Flattens `request.config.systemInstruction`, conversation `request.contents`, and any declared `request.toolsDict` declarations into a structured Gemma prompt.
  - When tools are attached to the active `Agent` (`budget_auditor_agent` or `concierge_agent`) and no tool response has yet been supplied in the current turn, instructs Gemma to emit a strict `<tool_call>{"name": "...", "args": {...}}</tool_call>` JSON block (with a deterministic fallback extractor if the model outputs raw JSON or prose numbers), returning an `LlmResponse` containing `Part.fromFunctionCall(...)` so `flutter_adk`'s `Runner` executes the real `FunctionTool` and emits native ADK tool-call / tool-response events to `AdkChatView` and `AdkToolInspectorView`.
- **Optional LAN Mode (`LiteLlm`)**:
  - Users can toggle between **`LlmEngineMode.onDeviceLiteRt`** (default, 100% standalone inside the phone) and **`LlmEngineMode.lanOllama`** (`LiteLlm(model: 'ollama_chat/gemma3:4b', baseUrl: 'http://<host>:11434/v1')`) via `LlmEngineConfig`.

### 2. Root `CoordinatorAgent` (`LlmAgent`) + 3-Agent `SequentialAgent` Pipeline (`pocket_squad_pipeline`)
Constructed by `PocketSquadAgentFactory` (`lib/data/agents/pocket_squad_agent_factory.dart`):
0. **Root Agent — `coordinator_agent` (`LlmAgent`, `subAgents: [pocket_squad_pipeline]`)**:
   - Acts as the conversational front-desk Travel Coordinator.
   - Evaluates the multi-turn conversation history (`TripIntakeReadiness`) for the 3 required trip parameters: **1) Destination (city/country)**, **2) Duration (days/nights)**, and **3) Budget (amount/currency)**.
   - **Conversational Intake Mode (Missing parameters)**: When the user greets (`"Hola"`, `"Hi"`) or provides partial details (e.g., `"Quiero ir a Tokio"` without days or budget), `coordinator_agent` responds naturally in the user's language asking only for the missing fields without triggering the specialist pipeline.
   - **Pipeline Handoff Mode (All 3 parameters present)**: Once Destination + Days + Budget are present across the conversation turns (or in a single prompt), `coordinator_agent` invokes ADK's built-in `transfer_to_agent(agent_name: 'pocket_squad_pipeline')` tool, delegating execution to the 3-agent `SequentialAgent`:
1. **Sub-Agent 1 — `scout_agent` (`Agent`, 0 tools, 100% Native LLM Knowledge)**:
   - Uses Gemma's pre-trained world knowledge to generate destination neighborhoods, iconic & hidden-gem spots, a day-by-day route, local transport tips, and realistic per-day USD cost estimates (`days`, `lodging_per_night_usd`, `food_per_day_usd`, `activities_total_usd`, `target_currency`, `user_budget_usd`) for any city on Earth.
   - Writes its output to `session.state['itinerary_draft']` (`outputKey: 'itinerary_draft'`).
2. **Sub-Agent 2 — `budget_auditor_agent` (`Agent`, 1 `FunctionTool`: `calculate_budget_math`)**:
   - Reads `{itinerary_draft}` from `session.state`.
   - Invokes `calculate_budget_math` (`FunctionTool`) to compute exact deterministic arithmetic:
     - `lodgingTotalUsd = days * lodgingPerNightUsd`
     - `foodTotalUsd = days * foodPerDayUsd`
     - `subtotalUsd = lodgingTotalUsd + foodTotalUsd + activitiesTotalUsd`
     - `contingencyBufferUsd = subtotalUsd * 0.10` (10% buffer)
     - `grandTotalUsd = subtotalUsd + contingencyBufferUsd`
     - Currency conversion (`USD`, `EUR`, `JPY`, `GBP`, `MXN`, `COP`) and `budgetDeltaUsd = userBudgetUsd - grandTotalUsd` (`withinBudget`).
   - Writes its audit report to `session.state['budget_audit']` (`outputKey: 'budget_audit'`).
3. **Sub-Agent 3 — `concierge_agent` (`Agent`, 1 `FunctionTool`: `save_trip_plan`)**:
   - Reads `{itinerary_draft}` and `{budget_audit}` from `session.state`.
   - Calls `save_trip_plan` (`FunctionTool`) to persist a `SavedTrip` record into local device storage (`SavedTripsRepository` / `AppStorageService` backed by `SharedPreferences`) so it appears immediately in the **Saved Trips Vault** tab.
   - Synthesizes the final executive travel brief and packing checklist into `session.state['final_concierge_brief']` (`outputKey: 'final_concierge_brief'`).

## Consequences & Reviewer Compliance Rules

- **Positive**: Natural multi-turn chat intake for greetings/follow-ups (~1 fast turn) combined with 100% offline/on-device 3-agent sequential execution once trip parameters are known; ~0.8 GB RAM footprint; zero fake POI databases; authentic deterministic arithmetic and persistence tools.
- **Compliance Rules for `flutter-reviewer`**:
  1. `LiteRtChatDriver` MUST be a single shared instance across `coordinator_agent` and all 3 sub-agents (`scout_agent`, `budget_auditor_agent`, `concierge_agent`).
  2. `coordinator_agent` MUST NOT transfer to `pocket_squad_pipeline` until Destination, Days, and Budget have been provided in the conversation.
  3. `scout_agent` MUST NOT use any hardcoded city/POI lookup tool.
  4. `calculate_budget_math` and `save_trip_plan` MUST be registered as real `FunctionTool` instances on `budget_auditor_agent` and `concierge_agent` respectively.
