# PLAN — `apps/a2ui/` regroup + Snap & Sell with Jev (decision model)

Targets: `apps/a2ui/snap_sell` (v0.9, moved), `apps/a2ui/snap_sell_express` (1.0 + Express, moved), `apps/a2ui/snap_sell_jev` (new).
Pattern: Jev decides, Gemini writes, code assembles ([jev2ui](https://github.com/dglazkov/jev2ui)). ADR: `apps/a2ui/snap_sell_jev/doc/adr/0008-jev-decision-model.md`.

| # | Task | Owner | Files | Status |
|---|------|-------|-------|--------|
| A1 | Move both apps under `apps/a2ui/`, fix README/doc/memory paths, regenerate `.venv` and Flutter files | main | `apps/a2ui/**`, `README.md`, `context/memory/**` | done |
| A2 | Separate Cloud Run services (`snap-sell-express-agent`, `snap-sell-jev-agent`) so v0.9 is not overwritten | main | `*/agent/cloudbuild.yaml`, `*/mobile/config/prod*.json` | done |
| B1 | Copy Express app as `snap_sell_jev`; title "Snap & Sell · Jev" | main | `apps/a2ui/snap_sell_jev/**` | done |
| B2 | Agent: `jev_client.py`, `decisions.py`, `writer.py`, `surfaces.py`, `flow.py`, `SnapSellJevAgent` (ADK `BaseAgent`), A2A converters for blobs + trace | main | `snap_sell_jev/agent/app/**` | done |
| B3 | Tests: decisions, flow with fake Jev/writer, ADK runner, A2A SSE e2e, Flutter render of Jev-built surfaces | main | `agent/tests/**`, `mobile/test/catalog/jev_surfaces_render_test.dart`, `contracts/examples/jev/**` | done |
| B4 | Docs: ADR 0008, app README with 3-variant comparison, root README | main | `doc/**`, `README.md` | done |

## Exit criteria
- `uv run pytest` + `ruff check` green in each agent; `dart analyze` + `flutter test` green in each mobile app.
- Every surface built by `surfaces.py` validates against the catalog and renders in `a2ui_flutter`.

## Result (2026-11-21)
- snap_sell: agent 20 tests, mobile 43 tests. snap_sell_express: agent 32, mobile 46. snap_sell_jev: agent 62, mobile 53.
- Live Jev + Gemini turn pending: needs `JEV_API_KEY` and Gemini credentials.

## Risks
- Question wording and thresholds are untested on real photos (needs an eval with a key).
- Jev image support (`typesafe-sdk` `Image` asset) verified only against the SDK, not the live API.

## Approved demo/dev fallbacks (same approval as the Express copy, 2026-11-21)
- demo-data: approved apps/a2ui/snap_sell_jev/agent/app/app_utils/services.py — in-memory ADK session/artifact services only when no SESSION_SERVICE_URI / Agent Engine / LOGS_BUCKET_NAME is configured.
- demo-data: approved apps/a2ui/snap_sell_jev/agent/app/fast_api_app.py — `InMemoryTaskStore`, the a2a-sdk standard A2A task store.
- demo-data: approved apps/a2ui/snap_sell_jev/mobile/lib/ui/catalog/snap_sell_contract.g.dart — sample names from the official Basic Catalog instructions.
- demo-data: approved apps/a2ui/snap_sell_jev/agent/scripts/export_jev_surfaces.py — dev tool that runs the flow with the test stand-ins to write `contracts/examples/jev/*.json` for the Flutter render tests; never used by the app.
- demo-data: approved apps/a2ui/snap_sell_jev/agent/app/jev_client.py — only the `DecisionEngine` docstring mentions the test stand-in; production uses `TypeSafeJev` (real TypeSafe API).
