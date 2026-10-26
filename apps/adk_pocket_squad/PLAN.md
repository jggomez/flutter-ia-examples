# PLAN — `apps/adk_pocket_squad` (Pocket Squad: 100% On-Device Multi-Agent Travel & Budget Concierge)

## 1. Objective & Scope

Build **App 5 (`apps/adk_pocket_squad`)**, a production-grade, 100% on-device Multi-Agent Flutter application powered by:
- **`flutter_adk` (`^2026.10.23`)** (`package:flutter_adk/flutter_adk.dart` + `package:adk_dart/adk_core.dart`)
- **On-Device `Gemma 4 E2B IT (2.58 GB)` (`gemma-4-E2B-it.litertlm`)** via `flutter_edge_ai` (`^0.1.3`) + `flutter_edge_ai_litertlm` (`^0.1.3+1`) on `PreferredBackend.cpu` (`mmap` ~0.8 GB RAM)
- **Dual-Mode Local LLM Bridge**:
  1. **On-Device LiteRT-LM FFI (`OnDeviceLiteRtGemmaLlm extends BaseLlm`) [Default]**: Runs 100% standalone inside the phone (`0` external servers required). All 3 agents in the `SequentialAgent` pipeline share the single loaded 2.58 GB model instance in RAM.
  2. **Local LAN Ollama / LM Studio (`LiteLlm`)**: Optional toggle in Settings using `LiteLlm(model: 'ollama_chat/gemma3:4b', baseUrl: 'http://<host>:11434/v1')` from `flutter_adk#local-llm-quickstart-ollama--lm-studio`.
- **Authentic LLM vs. `FunctionTool` Boundary**:
  - **100% Native LLM Knowledge (`ScoutAgent`)**: Gemma uses its own pre-trained knowledge to design spots, neighborhoods, day-by-day itineraries, seasonal weather context, and estimated local costs for any city worldwide (zero artificial/hardcoded POI dictionaries).
  - **Tool 1 — Exact Arithmetic & Currency (`calculate_budget_math` in `BudgetAuditorAgent`)**: Eliminates 2B model arithmetic hallucinations by computing exact multi-day totals, 10% contingency buffers, target currency conversions, and budget delta checks (`withinBudget`).
  - **Tool 2 — Local Device Persistence (`save_trip_plan` in `ConciergeAgent`)**: Saves the finalized trip brief and budget breakdown into local device storage (`SharedPreferences` / local repository) so users can browse saved trips in the **Saved Trips Vault** tab.
- **Native Wi-Fi `MethodChannel` (`com.jggomez.flutterai.adk_pocket_squad/network`)**:
  - Same proven architecture as `rag_study_gemma`: `MainActivity.kt` queries `ConnectivityManager` (`NetworkCapabilities.TRANSPORT_WIFI`) to prevent accidental 2.58 GB cellular downloads and verify Wi-Fi before probing LAN Ollama.

---

## Discovery & Architecture Triage

| Rubric Criterion | Applies? | Justification | Action |
| :--- | :---: | :--- | :--- |
| `>= 2` screens, widgets, or notifiers/controllers created or modified | **YES** | Creates `ModelDownloadScreen`, `PocketSquadWorkspaceScreen` (with 4 rich experiences: Mission Chat, Live Pipeline & State, Saved Trips Vault, and `AdkDevStudioView`), plus `ModelDownloadViewModel` and `PocketSquadViewModel`. | **MUST INVOKE `flutter-architect`** |
| State management (`Riverpod` / `ChangeNotifier` / `AdkChatController`) contracts change | **YES** | Integrates `flutter_riverpod` (`^3.0.3`) with `flutter_adk` controllers (`AdkChatController`, `AdkWorkflowStep`) and `SequentialAgent` session state (`itinerary_draft`, `budget_audit`, `final_concierge_brief`). | **MUST INVOKE `flutter-architect`** |
| Navigation / multi-screen flow changes | **YES** | Readiness gate (`ModelDownloadScreen` → `PocketSquadWorkspaceScreen`) with engine mode switcher sheet. | **MUST INVOKE `flutter-architect`** |
| Platform channels, FFI, or native plugins (`pubspec.yaml`) added | **YES** | Adds `flutter_adk`, `flutter_edge_ai`, `flutter_edge_ai_litertlm`, `shared_preferences`, `path_provider`, `http`, plus native Android `MethodChannel('com.jggomez.flutterai.adk_pocket_squad/network')`. | **MUST INVOKE `flutter-architect`** |

---

## Parallel Execution Tracks

### Phase 0 — Foundation, Scaffolding & Core Services (`flutter-implementer`)
- **Mode**: Sequential Foundation Setup
- **Owned Files**:
  - `apps/adk_pocket_squad/pubspec.yaml`
  - `apps/adk_pocket_squad/analysis_options.yaml`
  - `apps/adk_pocket_squad/android/**` (including `MainActivity.kt` with `MethodChannel('com.jggomez.flutterai.adk_pocket_squad/network')`, `minSdk = 26`, `INTERNET` + `ACCESS_NETWORK_STATE`)
  - `apps/adk_pocket_squad/lib/domain/**`
  - `apps/adk_pocket_squad/lib/data/services/network_connectivity_service.dart`
  - `apps/adk_pocket_squad/lib/data/services/model_download_service.dart`
  - `apps/adk_pocket_squad/lib/data/services/app_storage_service.dart`

### Phase 1 — Parallel Fan-Out (`Workspace: 'inherit'`, Disjoint File Partitioning)
- **Track A — ADK Multi-Agent Engine, `OnDeviceLiteRtGemmaLlm` Bridge & Real Tools (`flutter-implementer`)**:
  - **Owned Files**:
    - `apps/adk_pocket_squad/lib/data/llm/**` (`on_device_litert_gemma_llm.dart`, `litert_chat_driver.dart`, `llm_engine_config.dart`)
    - `apps/adk_pocket_squad/lib/data/agents/**` (`pocket_squad_tools.dart`, `pocket_squad_agent_factory.dart`)
    - `apps/adk_pocket_squad/lib/data/repositories/**`
    - `apps/adk_pocket_squad/test/data/**`
- **Track B — Luxury Travel Concierge UI/UX, `flutter_adk` Widgets & ViewModels (`flutter-implementer`)**:
  - **Owned Files**:
    - `apps/adk_pocket_squad/lib/ui/**` (`theme/`, `providers/`, `screens/`, `widgets/`, `view_models/`)
    - `apps/adk_pocket_squad/lib/main.dart`
    - `apps/adk_pocket_squad/test/ui/**`
    - `apps/adk_pocket_squad/test/widget_test.dart`

## Finalized Architectural Decision Records (State 1)
- [ADR 0001 — 100% On-Device ADK + LiteRT-LM Multi-Agent Architecture & Authentic Tool Boundary](doc/adr/0001-on-device-adk-litert-multi-agent-architecture.md)
  - `LiteRtChatDriver`: Shared singleton wrapping `flutter_edge_ai` (`ModelType.gemma4`, `PreferredBackend.cpu`, `mmap` ~0.8 GB RAM).
  - `OnDeviceLiteRtGemmaLlm extends BaseLlm`: Bridges `adk_core.dart` `LlmRequest`/`LlmResponse`, evaluates `TripIntakeReadiness` (Destination + Days + Budget) across conversation turns for `coordinator_agent`, and parses `<tool_call>` JSON blocks into `Part.fromFunctionCall(...)` with deterministic fallback extraction.
  - Root `coordinator_agent` (`LlmAgent`, `subAgents: [pocket_squad_pipeline]`): Chats naturally with the user on greetings/follow-ups until Destination, Days, and Budget are known, then calls `transfer_to_agent(agent_name: 'pocket_squad_pipeline')`.
  - `SequentialAgent` (`pocket_squad_pipeline`):
    1. `scout_agent` (100% native LLM world knowledge, 0 tools → `outputKey: 'itinerary_draft'`)
    2. `budget_auditor_agent` (calls `calculate_budget_math` `FunctionTool` → `outputKey: 'budget_audit'`)
    3. `concierge_agent` (calls `save_trip_plan` `FunctionTool` → `outputKey: 'final_concierge_brief'`)
- [ADR 0002 — Native Wi-Fi `MethodChannel` & Atomic Model Download Pipeline](doc/adr/0002-wifi-method-channel-and-atomic-model-download.md)
  - Android `MethodChannel('com.jggomez.flutterai.adk_pocket_squad/network')` in `MainActivity.kt` (`NetworkCapabilities.TRANSPORT_WIFI`).
  - `ModelDownloadService`: manual redirect loop stripping `Authorization` across CDN hosts, atomic `.part` download, `>= 400 MB` size check.
- [ADR 0003 — Editorial Luxury Travel Concierge UX & `flutter_adk` Widget Integration](doc/adr/0003-travel-concierge-ux-and-adk-widget-integration.md)
  - "Horizon Obsidian & Sunset Amber/Teal" Material 3 theme (`PocketSquadTheme`).
  - 4-tab `PocketSquadWorkspaceScreen`: Squad Mission (`AdkChatView` + `AdkWorkflowProgressIndicator` + `AdkAgentHierarchyBadge` + `AdkToolCallCard`), Live Pipeline & State (`AdkWorkflowGraphView` + `session.state` inspector + `AdkToolInspectorView`), Saved Trips Vault (`SavedTrip` cards), and ADK Studio (`AdkDevStudioView`).

---

## Execution Checklist
- [x] **State 0**: Restore `context/memory/MEMORY.md` and author `apps/adk_pocket_squad/PLAN.md`.
- [x] **State 1**: Update ADRs (`0001..0003`) with Root `CoordinatorAgent` (`LlmAgent`) + `SequentialAgent` (`pocket_squad_pipeline`) handoff.
- [x] **State 2**: Execute Parallel Track A (Data/ADK Coordinator + Intake Readiness) & Track B (UI/UX Coordinator Badge & 4-Step Pipeline Header) via `flutter-implementer`.
- [x] **State 3 & 4**: Run `flutter-reviewer` (`32/32` tests passing, `0` analyze issues) and `flutter-release-engineer` + deploy and verify live on **OPPO Reno10 5G (`CPH2531` · `SSUS9P9DS4DIV8RC`)**.
- [x] **Phase 2 UX/UI & ADK Telemetry Refinement**:
  - [x] Remove suggestion bubbles (`AdkPromptSuggestionsBar`) above the main text input in **Squad Mission**.
  - [x] Hide tool execution cards (`transfer_to_agent`, `calculate_budget_math`, `save_trip_plan`) from **Squad Mission** chat and surface them in **Pipeline & State** and **ADK Studio**.
  - [x] Fix **ADK Studio → Live Logger** by maintaining persistent `AdkAgentLogEntry` telemetry in `PocketSquadViewModel` across all turns, tool calls, and `session.state` updates.
  - [x] Add **Final Result Dossier (`TripFinalResultSheet`)** in **Trips Vault** so users can inspect the complete final concierge brief, full day-by-day itinerary, budget audit, and checklist.
  - [x] Replace raw Markdown text in chat bubbles and dossiers with `FormattedAgentMessageView` (stripping internal `###` agent headers and rendering clean headings, bullets, and bold spans without raw `**`/`###` syntax).
  - [x] Extract Clean Architecture Domain Use Cases (`EvaluateTripIntakeUseCase`, `CalculateTripBudgetUseCase`, `SaveTripPlanUseCase` in `lib/domain/use_cases/`), enforce Day-by-Day (`Día 1..N` / `Day 1..N`) itinerary output in `ScoutAgent` (`maxOutputTokens: 550`), and split multi-agent responses into 3 separate specialist cards in **Squad Mission**.
- [x] **State 5**: Finalize `PLAN.md`, deploy updated APK to **OPPO Reno10 5G (`SSUS9P9DS4DIV8RC`)**, and update `context/memory/`.



