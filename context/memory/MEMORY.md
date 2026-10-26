# MEMORY — flutter-ai (Cross-AI LLM Wiki Home)

> Read this first (~500 tokens). Drill into topic pages only on demand.

## 1. Active Handoff State
- **Last host**: Antigravity · **Branch**: `main`
- **Just completed** (2026-10-25):
  - `apps/adk_pocket_squad` (**Pocket Squad** — App 5): 100% On-Device Hierarchical + Sequential Multi-Agent Travel & Budget Concierge built with `flutter_adk` (`^2026.10.23` / `package:adk_dart/adk_core.dart`) and **`Gemma 4 E2B IT (2.58 GB)`** (`gemma-4-E2B-it.litertlm`, `ModelType.gemma4`, `PreferredBackend.cpu`, `mmap` ~0.8 GB RAM):
    - Added Root Conversational `coordinator_agent` (`LlmAgent`, `subAgents: <BaseAgent>[pipelineAgent]`) + multi-turn `TripIntakeReadiness` evaluator in `OnDeviceLiteRtGemmaLlm`: greets the user naturally in Spanish or English (e.g. `"Hola"`) and collects **Destination + Duration (days) + Budget** across turns before invoking ADK's `transfer_to_agent(agent_name: 'pocket_squad_pipeline')`.
    - Built 3-agent `SequentialAgent` (`pocket_squad_pipeline`) sharing one `LiteRtChatDriverImpl` singleton:
      1. `scout_agent`: 100% native LLM world knowledge (`0` tools) → `outputKey: 'itinerary_draft'`.
      2. `budget_auditor_agent`: Calls `calculate_budget_math` (`FunctionTool`) for exact multi-day arithmetic, 10% buffer, currency conversion (`JPY`, `COP`, `EUR`, `GBP`, `MXN`, `USD`), and budget delta → `outputKey: 'budget_audit'`.
      3. `concierge_agent`: Synthesizes executive travel brief & packing checklist and calls `save_trip_plan` (`FunctionTool`) to persist a `SavedTrip` to local storage → `outputKey: 'final_concierge_brief'`.
    - Extracted Clean Architecture Domain Use Cases (`EvaluateTripIntakeUseCase`, `CalculateTripBudgetUseCase`, `SaveTripPlanUseCase` in `lib/domain/use_cases/`), enforced Day-by-Day (`Día 1..N` / `Day 1..N` Morning/Afternoon/Evening places) in `scout_agent` (`maxOutputTokens: 550`), split multi-agent responses into 3 separate specialist cards in `Squad Mission`, wired persistent `AdkAgentLogEntry` live telemetry in `ADK Studio -> Live Logger`, and added the full `View Final Result & Full Itinerary` modal sheet in `Trips Vault`.
    - Normalized 8 physical-device screenshots in `images/adk_pocket/01-..08-..jpeg` and authored comprehensive English documentation in `apps/adk_pocket_squad/README.md` and the root monorepo `README.md` with Mermaid architecture diagrams.
- **Verified 2026-10-25**:
  - `apps/adk_pocket_squad` — `flutter analyze` clean (0 issues) ✅, `flutter test` 36/36 ✅, live on-device run & 8-screenshot gallery on physical Android device with 2.58 GB `gemma-4-E2B-it.litertlm` staged ✅
  - `apps/rag_study_gemma` — `flutter analyze` clean (0 issues) ✅, `flutter test` 78/78 ✅, live on-device run & benchmarks on physical Android device ✅
  - `apps/event_gemma` — `flutter analyze` clean (0 issues) ✅, `flutter test` 147/147 ✅
  - `apps/rps_live` — `flutter analyze` clean ✅, `flutter test` 77/77 ✅
  - `apps/a2ui_snap_sell` — `agent/` (`uv run pytest` 20/20 ✅, Cloud Run live ✅), `mobile/` (`flutter analyze` clean ✅, `flutter test` 43/43 ✅)
- **No root `PLAN.md`**; each app owns `apps/<app>/PLAN.md`.

### Next steps (priority order)
1. Optional screen recording `.gif`/`.mp4` for `apps/adk_pocket_squad` if desired by the user.

## 2. Key Architecture & Conventions (summary)
- Independent apps, no shared package; identical Flutter layering `domain / data / ui` → [architecture.md](./architecture.md)
- Riverpod 3.x manual providers, `.autoDispose` VMs (exceptions: `event_gemma` `chatViewModelProvider`, `a2ui_snap_sell` selling session VM, `rag_study_gemma` `studyChatViewModelProvider`, `adk_pocket_squad` `pocketSquadViewModelProvider`).
- `adk_pocket_squad`: Root `coordinator_agent` (`LlmAgent` conversational intake + `transfer_to_agent`) → `SequentialAgent` (`scout_agent` -> `budget_auditor_agent` -> `concierge_agent`) sharing one `LiteRtChatDriver` (`Gemma 4 E2B IT` 2.58 GB on CPU `mmap`) + optional `LiteLlm` LAN Ollama.
- `rag_study_gemma`: Dual-model LiteRT-LM (`Gemma 4 E2B IT`, `ModelType.gemma4`, `PreferredBackend.cpu`, `maxTokens: 2048`) + Embeddings 2.0 (`EmbeddingGemma 2` 768-dim on CPU backend) + `SqliteVectorStoreProvider` (`vec0`) + `Isolate.run()` pure-Dart PDF extraction (`syncfusion_flutter_pdf`).
- TDD with fakes; native/transport wrappers isolated in `data/services/`; regression tests for engine/session lifecycles.
- Secrets/config via `--dart-define-from-file`, `**/*.local.json` gitignored → [conventions.md](./conventions.md)
- ADRs: `apps/rps_live/doc/adr/0001-0003`, `apps/event_gemma/doc/adr/0001-0007`, `apps/a2ui_snap_sell/doc/adr/0001-0006`, `apps/rag_study_gemma/doc/adr/0001-0005`, `apps/adk_pocket_squad/doc/adr/0001-0003`.

## 3. Recent Daily Logs
- [2026-10-25.md](./log/2026-10-25.md)
- [2026-10-24.md](./log/2026-10-24.md)
- [2026-10-22.md](./log/2026-10-22.md)
- [2026-10-21.md](./log/2026-10-21.md)
