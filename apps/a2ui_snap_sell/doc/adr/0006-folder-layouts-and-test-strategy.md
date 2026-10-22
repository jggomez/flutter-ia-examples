# 0006. Monorepo Folder Layouts (`agent/` and `mobile/`) and Dual-Track TDD Strategy

- **Status**: accepted
- **Date**: 2026-10-21
- **Deciders**: flutter-architect

## Context

`apps/a2ui_snap_sell/` contains two independent sub-projects that must be developed in parallel during State 2 (`Mode A: Disjoint File Partitioning`) without file collisions:
- **Track A (`apps/a2ui_snap_sell/agent/`)**: Python ADK + A2A + A2UI server.
- **Track B (`apps/a2ui_snap_sell/mobile/`)**: Flutter mobile client (Android + iOS).
- **Shared Contract (`apps/a2ui_snap_sell/contracts/`)**: Read-only during State 2.

Both sides must follow repository conventions (`context/memory/conventions.md`, `.agents/skills/a2ui-python-development/SKILL.md`, and `.agents/skills/flutter-apply-architecture-best-practices/SKILL.md`) and run fast, deterministic unit/widget tests offline without live network or Vertex AI calls.

## Decision

### 1. Python Agent Layout (`apps/a2ui_snap_sell/agent/`)

Generated via `agents-cli scaffold create snap-sell-agent --agent adk --deployment-target cloud_run --prototype --agent-guidance-filename GEMINI.md --region us-central1` (`google-agents-cli ~= 1.11.0`) and extended in-place with `a2ui-agent-sdk == 0.9.0`:

```text
apps/a2ui_snap_sell/agent/
├── agents-cli-manifest.yaml     # Official agents-cli project manifest
├── Dockerfile                   # Scaffolded Cloud Run container definition
├── GEMINI.md                    # Scaffolded agent guidance
├── README.md
├── pyproject.toml               # uv project (google-adk, a2a-sdk[http-server], a2ui-agent-sdk)
├── app/
│   ├── __init__.py              # Exports app / root_agent
│   ├── agent.py                 # MODEL="gemini-3.8-flash", root_agent, app = App(root_agent=root_agent, name="app")
│   ├── catalog.py               # Loads ../contracts/snap_sell_catalog.json + A2uiGenerator + A2uiRequestProcessor
│   ├── tools.py                 # 4 ADK tools (record_detected_item, validate_listing_fields, extract_odometer_reading, estimate_price_and_build_preview)
│   ├── fast_api_app.py          # Scaffolded FastAPI server + /a2a/app & / mounts + /uploads StaticFiles
│   └── app_utils/
│       ├── a2a.py               # Built-in ADK A2aAgentExecutor + A2UI v0.9 AgentExtension & Part Converters
│       └── services.py          # Scaffolded get_session_service() / get_artifact_service()
├── deployment/
│   └── terraform/single-project/ # Scaffolded Cloud Run Terraform IaC
└── tests/
    ├── eval/
    │   ├── eval_config.yaml     # ADK evaluation criteria (tool_trajectory_avg_score, response_match_score)
    │   └── datasets/
    │       └── basic-dataset.json # EvalSet cases for agents-cli eval run
    ├── unit/
    │   ├── test_catalog_contract.py # Validates snap_sell_catalog.json and all 5 contracts/examples/0.9/*.json
    │   ├── test_tools.py            # Pure-Python unit tests for all 4 ADK tools (zero LLM calls)
    │   └── test_a2a_a2ui.py         # Unit tests for A2UI v0.9 part converters & AgentCard extension
    └── integration/
        └── test_server_e2e.py       # FastAPI AgentCard & health endpoint smoke test
```

### 2. Flutter Mobile Layout (`apps/a2ui_snap_sell/mobile/`)

Follows the monorepo `domain / data / ui` layering (`ui` → `domain` ← `data`):

```text
apps/a2ui_snap_sell/mobile/
├── pubspec.yaml
├── analysis_options.yaml
├── config/
│   ├── dev.emulator.json
│   ├── dev.ios_sim.json
│   └── prod.cloudrun.json
├── lib/
│   ├── main.dart                                      # ProviderScope overrides + app bootstrap
│   ├── app.dart                                       # MaterialApp + theme + SellingFlowRoot
│   ├── core/
│   │   ├── config/
│   │   │   └── app_config.dart                        # String.fromEnvironment constants
│   │   └── theme/
│   │       └── app_theme.dart                         # Material 3 marketplace theme
│   ├── domain/
│   │   ├── models/
│   │   │   ├── captured_photo.dart                    # Immutable bytes, mimeType, fileName
│   │   │   ├── selling_flow_status.dart               # Enum + SellingFailure value object
│   │   │   └── agent_turn_update.dart                 # Sealed domain events (working text, surface added/updated, completed, error)
│   │   └── repositories/
│   │       ├── image_capture_repository.dart          # Abstract interface for camera/gallery pick
│   │       └── selling_agent_repository.dart          # Abstract interface wrapping GenUI Conversation/SurfaceController
│   ├── data/
│   │   ├── services/
│   │   │   ├── image_picker_service.dart              # Thin pass-through over package:image_picker
│   │   │   └── genui_agent_service.dart               # Thin wrapper owning A2uiAgentConnector, A2uiTransportAdapter, SurfaceController, Conversation
│   │   └── repositories/
│   │       ├── image_capture_repository_impl.dart     # Enforces 1280px/Q80 + 1.5MB cap
│   │       └── selling_agent_repository_impl.dart     # Maps GenUI streams/actions to domain updates
│   └── ui/
│       ├── providers/
│       │   └── repository_providers.dart              # Single DI composition root (throws until overridden)
│       ├── catalog/
│       │   ├── snap_sell_catalog.dart                 # Assembles BasicCatalogItems + 5 custom CatalogItems
│       │   └── items/
│       │       ├── step_progress_item.dart            # StepProgress CatalogItem + widget
│       │       ├── detected_item_card_item.dart       # DetectedItemCard CatalogItem + widget
│       │       ├── photo_request_item.dart            # PhotoRequest CatalogItem + widget
│       │       ├── price_range_item.dart              # PriceRange CatalogItem + widget
│       │       └── listing_preview_item.dart          # ListingPreview CatalogItem + widget
│       └── features/
│           └── selling/
│               ├── view_models/
│               │   └── selling_session_view_model.dart # SellingSessionViewModel + SellingSessionState
│               └── views/
│                   ├── entry_screen.dart              # Fixed "¿Qué quieres vender?" screen
│                   ├── dynamic_surface_host_screen.dart # Renders active A2UI Surface + PopScope stack + loading overlay
│                   └── widgets/
│                       └── processing_banner.dart     # Streaming status indicator + cancel button
└── test/
    ├── support/
    │   └── fakes.dart                                 # FakeImageCaptureRepository, FakeSellingAgentRepository + in-memory SurfaceController helper
    ├── unit/
    │   ├── data/
    │   │   ├── image_capture_repository_impl_test.dart
    │   │   └── selling_agent_repository_impl_test.dart
    │   ├── catalog/
    │   │   └── snap_sell_catalog_test.dart            # Schema & contract parity test against ../contracts/examples/0.9/*.json
    │   └── view_models/
    │       └── selling_session_view_model_test.dart
    ├── widget/
    │   ├── entry_screen_test.dart
    │   ├── dynamic_surface_host_screen_test.dart
    │   └── catalog_items_widget_test.dart             # Widget tests for all 5 custom catalog components + DataModel binding + UserActionEvent dispatch
    └── regression/
        └── session_lifecycle_regression_test.dart     # Verifies dispose() / resetSession() leak-free teardown
```

## Alternatives considered

- **Placing Python agent files at the root of `agent/` without `src/` layout** — rejected because `.agents/skills/a2ui-python-development/SKILL.md` mandates `src/` package layout with curated `__init__.py` facades and `__all__`.
- **Embedding `SurfaceController` directly inside Flutter `Widget` states (as in `docs/a2ui/flutter-genui-get-started.md`)** — rejected because it couples UI widgets directly to `genui_a2a` network transport and violates the monorepo's `ui → domain ← data` architecture and fake-based TDD strategy.

## Consequences

- **Positive**: Track A (`agent/**`) and Track B (`mobile/**`) have 100% disjoint file ownership and can execute in parallel in Mode A (`Workspace: 'inherit'`).
- **Positive**: Both tracks test against `contracts/snap_sell_catalog.json` and `contracts/examples/0.9/*.json` offline, guaranteeing end-to-end compatibility before live Cloud Run verification.
- **Trade-off**: Wrapping `SurfaceController` behind `SellingAgentRepository` requires exposing `SurfaceHost` (`SurfaceContext Function(String surfaceId)`) on the repository interface so Flutter's `Surface(surfaceContext: ...)` widget can render surfaces in both production and widget tests (where `FakeSellingAgentRepository` uses a real in-memory `SurfaceController(catalogs: [snapSellCatalog])` without network I/O).

## Compliance

`flutter-reviewer` checks:
- Track A passes `uv run mypy src tests` and `uv run pytest` with zero network calls.
- Track B passes `flutter analyze` and `flutter test` with zero network calls.
- `FakeSellingAgentRepository` in `test/support/fakes.dart` drives a real in-memory `SurfaceController` fed with the JSON fixtures from `../contracts/examples/0.9/*.json` so widget tests exercise genuine A2UI rendering.
