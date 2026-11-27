# snap_sell_express — Plan

> Status: **implemented and verified offline**. A live Gemini run is still pending (needs Vertex AI credentials).
> Updated: 2026-11-21 · Migration plan: [`docs/a2ui-snap-sell-v1-express/PLAN.md`](../../docs/a2ui-snap-sell-v1-express/PLAN.md)

## Goal
Same product as `apps/a2ui/snap_sell` (v0.9, kept as reference) on A2UI 1.0:
`a2ui_flutter` renderer, A2UI Express inference format, v1.0 wire protocol, A2A transport.

## Decisions
See [ADR 0007](doc/adr/0007-a2ui-v1-express.md). ADRs 0001–0006 still apply except where 0007 supersedes them.

## Verification (2026-11-21)
| Check | Result |
|---|---|
| `agent`: `uv run pytest` | 32 passed |
| `agent`: `ruff check` / `ruff format --check` | clean |
| `mobile`: `dart analyze` | no issues |
| `mobile`: `flutter test` | 46 passed (5 examples render, components, A2A client/service, view model) |
| Live Dart renderer ↔ Python agent `callAgentFunction` (local uvicorn) | 3 verdicts returned, no LLM |
| Live Gemini turn | **not run**: no usable Vertex AI / Gemini credentials in this environment |

## Next
- Run the end-to-end flow on an emulator with credentials (`config/local.json`).
- Compare Express against v0.9 Direct JSON for latency and tokens with `tests/eval`.
