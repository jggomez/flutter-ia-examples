# MEMORY — flutter-ai (Cross-AI LLM Wiki Home)

> Read this first (~500 tokens). Drill into topic pages only on demand.

## 1. Active Handoff State
- **Last host**: Antigravity · **Branch**: `main`
- **Just completed** (2026-10-22):
  - `apps/event_gemma`: Completed full documentation and README overhaul with on-device physical screenshots (`images/event_gemma/01..07`): Agenda, Session Details, Onboarding Wi-Fi Check, Download Progress, Prompt Pills, Grounded Keynote Citations, and Topic Search.
  - `apps/event_gemma`: Completed ADR 0007 (Bilingual Lexical RAG, Hybrid Grounding) and ADR 0006 (`flutter_edge_ai_litertlm` migration + Material 3 AI/tech UI redesign). Rebranded across all code, tests, and platforms.
  - All READMEs synchronized (`README.md`, `apps/event_gemma/README.md`, `apps/rps_live/README.md`, `apps/a2ui_snap_sell/README.md`).
- **Verified 2026-10-22**:
  - `apps/event_gemma` — `flutter analyze` clean (0 issues) ✅, `flutter test` 147/147 ✅, verified on physical device `CPH2531` with Impeller Vulkan engine & 120Hz display ✅
  - `apps/rps_live` — `flutter analyze` clean, `flutter test` 77/77 ✅, verified on `CPH2531` ✅
  - `apps/a2ui_snap_sell/agent` — `agents-cli info` ✅, `agents-cli lint` clean ✅, `uv run pytest` 20/20 ✅, Cloud Run live (`devhack-3f0c2`, 512MiB, 1 vCPU throttled, min=0) ✅
  - `apps/a2ui_snap_sell/mobile` — `flutter analyze` clean ✅, `flutter test` 43/43 ✅, verified on `CPH2531` ✅
- **No root `PLAN.md`**; each app owns `apps/<app>/PLAN.md`.

### Next steps (priority order)
1. Ready for production release or next feature enhancement.

## 2. Key Architecture & Conventions (summary)
- Independent apps, no shared package; identical Flutter layering `domain / data / ui` → [architecture.md](./architecture.md)
- Riverpod 3.x manual providers, `.autoDispose` VMs (exceptions: `event_gemma` chat VM, `a2ui_snap_sell` selling session VM).
- Single DI composition root `ui/providers/repository_providers.dart`; providers throw until overridden in `main.dart`.
- `a2ui_snap_sell`: Dual-track app (`agent/` scaffolded with `google-agents-cli~=1.11.0` + `google-adk` + `a2ui-agent-sdk==0.9.0`; `mobile/` with `genui ^0.10.4` + `genui_a2a ^0.10.1`; shared contract in `contracts/snap_sell_catalog.json`).
- TDD with fakes; native/transport wrappers isolated in `data/services/`; regression tests for engine/session lifecycles.
- Secrets/config via `--dart-define-from-file`, `**/*.local.json` gitignored → [conventions.md](./conventions.md)
- ADRs: `apps/rps_live/doc/adr/0001-0003`, `apps/event_gemma/doc/adr/0001-0007`, `apps/a2ui_snap_sell/doc/adr/0001-0006`.

## 3. Recent Daily Logs
- [2026-10-22.md](./log/2026-10-22.md)
- [2026-10-21.md](./log/2026-10-21.md)
