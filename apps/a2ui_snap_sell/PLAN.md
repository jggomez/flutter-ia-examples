# a2ui_snap_sell — Plan

> Status: **State 5 Complete — Verified & Ready for Local Run / Cloud Run Deployment**
> Owner: flutter-feature-orchestrator · Architect: flutter-architect · Updated: 2026-10-21

## Goal
"Snap & Sell": the user snaps/uploads a photo of an item to sell (car, motorcycle, phone).
A Python ADK agent (Gemini multimodal on Vertex AI) identifies the item and **dynamically
generates the screens** (A2UI v0.9 surfaces) of a selling form: pre-filled detected fields,
only the questions the photo cannot answer (including EV vs. ICE branching), conditional
follow-up screens (e.g. "photo of the damage", "photo of the odometer" with Vision mileage
extraction, or field plausibility error recovery), and a final listing preview with a
suggested price range and mock publish flow.
The mobile app ships only a fixed entry screen; every other screen is agent-generated.

## Confirmed Decisions (user + environment verification, 2026-10-21)
| Topic | Decision |
|---|---|
| Use case | Snap & Sell |
| Categories (v1) | Cars (ICE & EV), motorcycles, phones (+ graceful unsupported-item card) |
| Model | Gemini (`gemini-3.8-flash` scaffold default) via **Gemini platform / Vertex AI**, GCP project **`devhack-3f0c2`**, `GOOGLE_CLOUD_LOCATION=global` (`GOOGLE_GENAI_USE_ENTERPRISE=true`) |
| Agent hosting & CLI | **`google-agents-cli` (`agents-cli~=1.11.0`)** scaffold (`--agent adk --deployment-target cloud_run --prototype`) + `agents-cli deploy` |
| App name / folder | `apps/a2ui_snap_sell/` with `agent/` (scaffolded via `agents-cli scaffold create`) + `mobile/` (Flutter 3.47.2) |
| Catalog ID | `https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json` (A2UI `v0.9`) |

## Discovery & Architecture Triage
| Rubric criterion | Applies? | Evidence |
|---|---|---|
| ≥2 screens/widgets/notifiers | ✅ | Entry screen, dynamic surface host, 5 custom catalog widgets (`StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`) |
| State management contracts | ✅ | Riverpod `Notifier` (`flutter_riverpod: ^3.4.3`) + GenUI `SurfaceController` + `DataModel` |
| Navigation routes | ✅ | Entry screen → stage-indexed agent-driven surface flow (`selling_step_1_detected` .. `selling_step_4_published`) |
| Native plugins / pubspec deps | ✅ | `image_picker: ^1.2.4`, `genui: ^0.10.4`, `genui_a2a: ^0.10.1`, `json_schema_builder: ^0.1.7`, `flutter_riverpod: ^3.4.3`, `mime: ^2.0.0` |
| Backend / cross-language contract | ✅ | Python ADK agent scaffolded with `agents-cli` (`google-adk[gcp,otel-gcp,bigquery-analytics]>=2.12.0`, `a2a-sdk[http-server]>=1.0,<2`, `a2ui-agent-sdk==0.9.0`) ↔ Flutter custom catalog |
| **Verdict** | **flutter-architect COMPLETED** | 6 ADRs + schema-validated catalog & 5 few-shot examples in `contracts/` |

## Architecture Deliverables (Completed in State 1)
- **ADRs (`apps/a2ui_snap_sell/doc/adr/`)**:
  - [ADR 0001 — Transport, A2A Session Management, and Image Upload Path](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0001-transport-a2a-image-upload.md)
  - [ADR 0002 — Agent Design, Multi-Step Selling Flow, Tools, Validation, and Surface ID Strategy](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0002-agent-design-and-surface-strategy.md)
  - [ADR 0003 — Shared Custom Catalog Contract (A2UI v0.9)](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0003-custom-catalog-contract.md)
  - [ADR 0004 — Flutter State Management, Navigation, and Image Capture](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0004-flutter-state-navigation-image-capture.md)
  - [ADR 0005 — Cloud Run Deployment, Vertex AI Auth, and Mobile Runtime Configuration](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0005-cloud-run-vertex-ai-config.md)
  - [ADR 0006 — Folder Layouts and Test Strategy for `agent/` and `mobile/`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/doc/adr/0006-folder-layouts-and-test-strategy.md)
- **Shared Catalog Contract (`apps/a2ui_snap_sell/contracts/`)** (validated with `a2ui-agent-sdk==0.9.0`):
  - [`snap_sell_catalog.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/snap_sell_catalog.json) — 12 standard `BasicCatalog` components + 5 custom components (`StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`).
  - [`CATALOG_CONTRACT.md`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/CATALOG_CONTRACT.md) — component properties, `/draft/...` & `/pricing/...` DataModel paths, `UserActionEvent` schemas, and surface IDs.
  - Few-shot examples (`contracts/examples/0.9/`):
    - [`01_detected_car.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/examples/0.9/01_detected_car.json)
    - [`02_followup_damage_odometer.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/examples/0.9/02_followup_damage_odometer.json)
    - [`03_detected_phone.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/examples/0.9/03_detected_phone.json)
    - [`04_listing_preview.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/examples/0.9/04_listing_preview.json)
    - [`05_unsupported_item.json`](file:///Users/jggomez/Documents/jggomez/code/flutter-ai/apps/a2ui_snap_sell/contracts/examples/0.9/05_unsupported_item.json)

## Parallel Execution Tracks (Finalized for State 2)
| Track | Agent | Mode | Owned Files | Read-Only Inputs |
|---|---|---|---|---|
| **Track A — Python ADK Agent (`agents-cli` scaffold)** | `code-implementer` (`senior-dev` plugin) | Mode A (`inherit`, disjoint files) | `apps/a2ui_snap_sell/agent/**` | `apps/a2ui_snap_sell/contracts/**`, `apps/a2ui_snap_sell/doc/adr/**`, `.agents/skills/google-agents-cli-*/**` |
| **Track B — Flutter Mobile App** | `flutter-implementer` (`senior-dev-flutter` plugin) | Mode A (`inherit`, disjoint files) | `apps/a2ui_snap_sell/mobile/**` | `apps/a2ui_snap_sell/contracts/**`, `apps/a2ui_snap_sell/doc/adr/**` |
| **Shared Contracts & ADRs** | Orchestrator / Architect only | Read-only in State 2 | `apps/a2ui_snap_sell/contracts/**`, `apps/a2ui_snap_sell/doc/adr/**`, `apps/a2ui_snap_sell/PLAN.md` | — |

### Track A (`apps/a2ui_snap_sell/agent/`) — Official `google-agents-cli` + ADK Workflow (`code-implementer`)
1. **Phase A1 — Official Scaffolding via `agents-cli`**:
   - Scaffold using `agents-cli scaffold create snap-sell-agent --agent adk --deployment-target cloud_run --prototype --agent-guidance-filename GEMINI.md --region us-central1` and move into `apps/a2ui_snap_sell/agent/` (preserving `agents-cli-manifest.yaml`, `app/fast_api_app.py`, `app/app_utils/a2a.py`, `app/app_utils/services.py`, `Dockerfile`, `deployment/terraform/`, `tests/eval/`, `tests/unit/`, `tests/integration/`).
   - Add `a2ui-agent-sdk==0.9.0` via `uv add a2ui-agent-sdk` without removing any scaffolded dependencies or altering `MODEL = "gemini-3.8-flash"`.
   - Set `.env` with `GOOGLE_GENAI_USE_ENTERPRISE=true`, `GOOGLE_CLOUD_PROJECT=devhack-3f0c2`, `GOOGLE_CLOUD_LOCATION=global`.
2. **Phase A2 — ADK Tools (`app/tools.py`) & State Callbacks Following `/google-agents-cli-adk-code`**:
   - Strictly follow ADK Tool Rules from `/google-agents-cli-adk-code`: type hints required, **NO default parameter values**, clear docstrings (do not mention `tool_context` in docstrings), return JSON-serializable `dict`, use `tool_context: ToolContext` for `tool_context.state[...]` access.
   - Let multimodal `gemini-3.8-flash` directly inspect the uploaded item photo and any follow-up odometer/damage photos passed by ADK's built-in `convert_a2a_part_to_genai_part` (`inline_data`).
   - Provide the 4 deterministic tools in `app/tools.py`: `record_detected_item`, `validate_listing_fields`, `extract_odometer_reading`, `estimate_price_and_build_preview`.
3. **Phase A3 — `app/agent.py` & Built-in A2A/A2UI Converter (`app/app_utils/a2a.py`)**:
   - In `app/agent.py`: preserve `MODEL = "gemini-3.8-flash"` and `app = App(root_agent=root_agent, name="app")`; build instruction via `A2uiGenerator` (`CatalogConfig.from_path` loading `snap_sell_catalog.json` + examples); use `before_agent_callback` to initialize session state and `after_model_callback` to validate `<a2ui-json>` blocks via `A2uiRequestProcessor`.
   - In `app/app_utils/a2a.py`: preserve the scaffolded `attach_a2a_routes` and `A2aAgentExecutor`; add the A2UI v0.9 `AgentExtension` (`https://a2ui.org/a2a-extension/a2ui/v0.9`) to `_default_capabilities()`, and pass a lightweight `A2aAgentExecutorConfig(gen_ai_part_converter=..., a2a_part_converter=...)` with `force_new_version=False` that converts `<a2ui-json>` blocks into A2A `DataPart`s (`mimeType: application/json+a2ui`) via `_compat.make_data_part` and converts incoming A2UI `{"action": ...}` `DataPart`s into user text/context for the ADK runner.
4. **Phase A4 — Unit Tests (`tests/unit/`) & Eval Config (`tests/eval/`)**:
   - Write unit tests in `tests/unit/` testing tool contracts, catalog validation, and the A2UI part converter (never assert on non-deterministic LLM text in `pytest` per `/google-agents-cli-workflow`).
   - Configure `tests/eval/eval_config.yaml` and `tests/eval/datasets/basic-dataset.json` per `/google-agents-cli-eval`.
   - Verify with `uv run pytest tests/unit tests/integration`, `agents-cli lint`, and `agents-cli info`.

### Track B (`apps/a2ui_snap_sell/mobile/`) — TDD Phase Breakdown (`flutter-implementer` — Completed)
1. **Phase B1 — Flutter Project Scaffold, Config & Contract Tests**: Completed (`config/local.json` pointing to `/a2a/app` on port 8000/8080).
2. **Phase B2 — 5 Custom Catalog Widgets (TDD)**: Completed (`StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`).
3. **Phase B3 — Transport Adapter, Session Controller & Entry/Host Screens (TDD)**: Completed (`32/32` tests passing, `flutter analyze` 0 issues).

## End-to-End & Cloud Run Verification Checklist (States 3–4)
- [x] Track A (`senior-dev`: `qa-tester` ∥ `compliance-verifier`): `cd apps/a2ui_snap_sell/agent && agents-cli info && agents-cli lint && uv run pytest tests/unit tests/integration` passes 100% (`20/20` tests, `0` lint issues) + `APPROVED` compliance verdict.
- [x] Track B (`senior-dev-flutter`: `flutter-reviewer` ∥ `flutter-release-engineer`): `cd apps/a2ui_snap_sell/mobile && flutter analyze && flutter test` passes with zero warnings (`32/32` tests) + 60/120fps & `.dispose()` audit `APPROVED`.
- [ ] Deploy agent to Cloud Run in GCP project `devhack-3f0c2` via `agents-cli deploy --mode prototype --project devhack-3f0c2 --region us-central1` (requires explicit user confirmation before deploying).

## State Checklist
- [x] State 0 — context restored, docs/skills fetched, PLAN written
- [x] State 1 — architecture + 6 ADRs + schema-validated shared contract (`snap_sell_catalog.json` + 5 examples)
- [x] State 2 — Track A (`code-implementer` with `google-agents-cli` skills) ∥ Track B (`flutter-implementer` completed)
- [x] State 3/4 — (`qa-tester` ∥ `compliance-verifier` for `agent/`) ∥ (`flutter-reviewer` ∥ `flutter-release-engineer` for `mobile/`) — ALL APPROVED
- [x] State 5 — ship + `context/memory/` update
