# PLAN — Snap & Sell on A2UI 1.0 + a2ui_flutter + Express

Target: `apps/a2ui/snap_sell_express` (copy of `apps/a2ui/snap_sell`, v0.9 kept as reference).
Transport: A2A JSON-RPC (unchanged backend topology, ADR 0001).

| # | Task | Owner | Files | Status |
|---|------|-------|-------|--------|
| 0 | Scaffold copy, new catalogId, port/token fixes | main | `apps/a2ui/snap_sell_express/**` | done |
| 1 | Contract v1.0: catalog (`protocolVersion 1.0`, `instructions`, `allowedParents`, `priceFeedback` agent fn) + examples 1.0 via `contracts/tools/migrate_to_v1.py` | main | `contracts/**` | done |
| 2 | Agent: `a2ui-agent-sdk 0.12`, `ExpressFormatFactory`, MIME `application/a2ui+json`, A2UI v1.0 A2A extension, `callAgentFunction` via `RendererToAgentMessageProcessor`, self-correction | main | `agent/app/**` | done |
| 3 | Flutter: `a2ui_flutter ^0.4.0` + `a2ui_core ^0.8.0`, `MessageProcessor`, own A2A client, `A2uiSurface`, `ComponentImplementation` catalog | main | `mobile/lib/**` | done |
| 4 | Tests (agent pytest, flutter test), ADR 0007, READMEs | main | `agent/tests/**`, `mobile/test/**`, `doc/**` | done |

## Exit criteria
- `uv run pytest` and `uv run ruff check` green in `agent/`.
- `dart analyze` and `flutter test` green in `mobile/`.
- Express block from the model compiles to `"version": "1.0"` messages validated against the catalog.

## Risks
- `a2ui-adk` API unread → keep custom A2A converters.
- Express grammar is a proposal; compiled server-side (Python), so the Dart compiler's multi-catalog gap does not apply.

## Result (2026-11-21)
All phases done. Agent: 32 tests passing, ruff clean. Mobile: `dart analyze` clean, 46 tests passing.
A live Dart↔Python `callAgentFunction` check passed. A live Gemini turn is still pending (needs credentials).

## Approved demo/dev fallbacks (user approved 2026-11-21)
- demo-data: approved apps/a2ui/snap_sell_express/agent/app/app_utils/services.py — in-memory ADK session/artifact services only when no SESSION_SERVICE_URI / Agent Engine / LOGS_BUCKET_NAME is configured.
- demo-data: approved apps/a2ui/snap_sell_express/agent/app/fast_api_app.py — `InMemoryTaskStore`, the a2a-sdk standard A2A task store.
- demo-data: approved apps/a2ui/snap_sell_express/mobile/lib/ui/catalog/snap_sell_contract.g.dart — sample names from the official Basic Catalog instructions.
