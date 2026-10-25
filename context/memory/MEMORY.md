# MEMORY — flutter-ai (Cross-AI LLM Wiki Home)

> Read this first (~500 tokens). Drill into topic pages only on demand.

## 1. Active Handoff State
- **Last host**: Antigravity · **Branch**: `main`
- **Just completed** (2026-10-25):
  - `apps/rag_study_gemma` (**StudyGemma** — App 4): Upgraded to **`Gemma 4 E2B IT (2.58 GB)`** (`gemma-4-E2B-it.litertlm`, `ModelType.gemma4`, `PreferredBackend.cpu`, `maxTokens: 2048`) and soft-wrap-healing sentence/newline-boundary chunking:
    - Upgraded Stage 2 LLM from `Gemma 3 1B IT` to **`Gemma 4 E2B IT`** (`litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`, mixed 2/4/8-bit quantization on `PreferredBackend.cpu` with `mmap` ~0.8 GB active RAM footprint, `enableThinking: false`, `temperature: 0.3, topK: 40, topP: 0.9, maxOutputTokens: 420`).
    - Refactored `ChunkDocumentUseCase` to heal soft PDF margin line wraps in justified prose (`AUTORIZACION DE CESION DE DERECHOS TECNOFEST.pdf`) while preserving structured line breaks (`\n`) and splitting prose strictly at sentence-ending periods (`.`, `!`, `?`) so chunks never end mid-phrase or mid-word ("mochos").
    - Added `BuildStudyPromptUseCase.selectBestChunks` (`topK: 8` candidates in `StudyChatViewModel`), stripping base64 seals, dropping seal-only chunks and substring fragments, and snapping excerpt cuts to `\n` or `.` boundaries (`520` chars max).
    - Authored comprehensive `apps/rag_study_gemma/README.md`, updated root `README.md` and ADRs (`0001`, `0002`, `0005`), and organized `images/rag_study/` with 6 high-res screenshots (`01`–`06`), full demo video (`study-gemma-demo.mp4`), and inline animated GIF preview (`00-study-gemma-demo.gif`).
- **Verified 2026-10-25**:
  - `apps/rag_study_gemma` — `flutter analyze` clean (0 issues) ✅, `flutter test` 78/78 ✅, live on-device run & benchmarks on `CPH2531` (~9.6–12.2s prefill, ~7.8–9.0 tok/s decode) ✅
  - `apps/event_gemma` — `flutter analyze` clean (0 issues) ✅, `flutter test` 147/147 ✅
  - `apps/rps_live` — `flutter analyze` clean ✅, `flutter test` 77/77 ✅
  - `apps/a2ui_snap_sell` — `agent/` (`uv run pytest` 20/20 ✅, Cloud Run live ✅), `mobile/` (`flutter analyze` clean ✅, `flutter test` 43/43 ✅)
- **No root `PLAN.md`**; each app owns `apps/<app>/PLAN.md`.

### Next steps (priority order)
1. All 4 apps (`rps_live`, `event_gemma`, `a2ui_snap_sell`, `rag_study_gemma`) are implemented, tested, verified on physical Android hardware, and documented with screenshots/video.

## 2. Key Architecture & Conventions (summary)
- Independent apps, no shared package; identical Flutter layering `domain / data / ui` → [architecture.md](./architecture.md)
- Riverpod 3.x manual providers, `.autoDispose` VMs (exceptions: `event_gemma` `chatViewModelProvider`, `a2ui_snap_sell` selling session VM, `rag_study_gemma` `studyChatViewModelProvider`).
- Single DI composition root `ui/providers/repository_providers.dart`; providers throw until overridden in `main.dart`.
- `rag_study_gemma`: Dual-model LiteRT-LM (`Gemma 4 E2B IT`, `ModelType.gemma4`, `PreferredBackend.cpu`, `maxTokens: 2048`, per-turn fresh `createChat` with explicit sampling & `maxOutputTokens: 420`) + Embeddings 2.0 (`EmbeddingGemma 2` 768-dim on CPU backend) + `SqliteVectorStoreProvider` (`vec0`) + `Isolate.run()` pure-Dart PDF extraction (`syncfusion_flutter_pdf`).
- TDD with fakes; native/transport wrappers isolated in `data/services/`; regression tests for engine/session lifecycles.
- Secrets/config via `--dart-define-from-file`, `**/*.local.json` gitignored → [conventions.md](./conventions.md)
- ADRs: `apps/rps_live/doc/adr/0001-0003`, `apps/event_gemma/doc/adr/0001-0007`, `apps/a2ui_snap_sell/doc/adr/0001-0006`, `apps/rag_study_gemma/doc/adr/0001-0005`.

## 3. Recent Daily Logs
- [2026-10-25.md](./log/2026-10-25.md)
- [2026-10-24.md](./log/2026-10-24.md)
- [2026-10-22.md](./log/2026-10-22.md)
- [2026-10-21.md](./log/2026-10-21.md)
