# MEMORY — flutter-ai (Cross-AI LLM Wiki Home)

> Read this first (~500 tokens). Drill into topic pages only on demand.

## 1. Active Handoff State
- **Last host**: Antigravity · **Branch**: `main` @ `86cb193`
- **Just completed** (2026-10-21):
  - `apps/event_llm_wiki`: Added native Android Wi-Fi connectivity check (`ConnectivityManager` + `TRANSPORT_WIFI` via `NetworkConnectivityService`), mandatory user confirmation dialog (`confirmModelDownloadDialog`) with optional runtime `HF_TOKEN` input, and Wi-Fi gate in `ModelDownloadRepositoryImpl.download()` (`doc/adr/0005` addendum); launched on physical Android device (`CPH2531`).
  - `apps/rps_live`: Verified on physical Android device (`CPH2531`); renamed and embedded all 6 real screenshots (`images/rsp_live/01..06`) + Mermaid pipeline diagram + contract/ADR tables into `apps/rps_live/README.md` and root `README.md`.
- **Verified 2026-10-21**:
  - `apps/rps_live` — `flutter analyze` clean, `flutter test` 77/77 ✅, verified on `CPH2531` ✅
  - `apps/event_llm_wiki` — `flutter analyze` clean, `flutter test` 122/122 ✅ (`flutter-reviewer` & `flutter-release-engineer` APPROVED), running on `CPH2531` ✅
  - `apps/a2ui_snap_sell/agent` — `agents-cli info` ✅, `agents-cli lint` clean ✅, `uv run pytest` 20/20 ✅, Cloud Run live (`devhack-3f0c2`, 512MiB, 1 vCPU throttled, min=0) ✅
  - `apps/a2ui_snap_sell/mobile` — `flutter analyze` clean ✅, `flutter test` 43/43 ✅, verified on `CPH2531` ✅
- **No root `PLAN.md`**; each app owns `apps/<app>/PLAN.md`.

### Next steps (priority order)
1. `event_llm_wiki`: Complete on-device Gemma 3 1B-IT download over Wi-Fi on `CPH2531`, test offline RAG chat & citations, and capture screenshots into `images/` for the READMEs.

## 2. Key Architecture & Conventions (summary)
- Independent apps, no shared package; identical Flutter layering `domain / data / ui` → [architecture.md](./architecture.md)
- Riverpod 3.x manual providers, `.autoDispose` VMs (exceptions: `event_llm_wiki` chat VM, `a2ui_snap_sell` selling session VM).
- Single DI composition root `ui/providers/repository_providers.dart`; providers throw until overridden in `main.dart`.
- `a2ui_snap_sell`: Dual-track app (`agent/` scaffolded with `google-agents-cli~=1.11.0` + `google-adk` + `a2ui-agent-sdk==0.9.0`; `mobile/` with `genui ^0.10.4` + `genui_a2a ^0.10.1`; shared contract in `contracts/snap_sell_catalog.json`).
- TDD with fakes; native/transport wrappers isolated in `data/services/`; regression tests for engine/session lifecycles.
- Secrets/config via `--dart-define-from-file`, `**/*.local.json` gitignored → [conventions.md](./conventions.md)
- ADRs: `apps/rps_live/doc/adr/0001-0003`, `apps/event_llm_wiki/doc/adr/0001-0005`, `apps/a2ui_snap_sell/doc/adr/0001-0006`.

## 3. Recent Daily Logs
- [2026-10-21.md](./log/2026-10-21.md)
