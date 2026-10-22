# Architecture Digest (living — update in place)

Monorepo of **independent** Flutter apps (no shared package) + training notebooks.
Full rationale lives in each app's `doc/adr/`; this page is the digest.

## Repo layout
```text
flutter-ai/
├── notebooks/                 # RPS CNN training (Kaggle drgfreeman/rockpaperscissors)
├── apps/rps_live/             # App 1 — live-camera RPS classifier game (LiteRT)
├── apps/event_llm_wiki/       # App 2 — offline conference wiki + on-device RAG chat (Gemma 3 1B)
├── apps/a2ui_snap_sell/       # App 3 — "Snap & Sell" dynamic A2UI v0.9 + Flutter GenUI marketplace app (agent/ + mobile/ + contracts/)
├── docs/a2ui/                 # Reference docs for ADK A2UI & Flutter GenUI
├── .agents/                   # Antigravity: official flutter/dart + google-agents-cli + a2ui skills + senior-dev/senior-dev-flutter plugins
├── .claude/                   # Claude Code: senior-dev-flutter plugin
└── context/memory/            # this cross-AI LLM Wiki
```

## Shared cross-app pattern
- Layers: `lib/domain/` (models, repo interfaces, use cases) → `lib/data/` (services, repo impls, DTOs, local) → `lib/ui/` (features/<f>/{views,view_models}, core/widgets).
- DI: single composition root `lib/ui/providers/repository_providers.dart`; providers **throw until overridden** in `main.dart`.
- State: `flutter_riverpod ^3.4.3`, manual (non-codegen) `Notifier`/`AsyncNotifier`, view models `.autoDispose` by default.
- Persistence: Hive (`hive` + `hive_flutter`, `hive_generator`/`build_runner` for `*.g.dart` DTO adapters).
- Native/plugin wrappers (camera, LiteRT engine) are thin, deliberately untested pass-through services; everything else is TDD with fakes (`test/support/fakes.dart`), plus `test/regression/` lifecycle tests.

## apps/rps_live
- Model: 29,235-param CNN, input 96x96 grayscale `[0,1]`, softmax order `paper, rock, scissors`. Asset `assets/models/rps_model.tflite` = **float32-I/O mobile export** (not the INT8 ESP32 build).
- Runtime: `flutter_litert ^3.8.0` + `camera ^0.12.1` (defaults to `CameraLensDirection.front` with live `switchCamera()` toggle); `PreprocessFrameUseCase` crops/resizes/grayscales off the UI thread, produces upright/selfie-mirrored `previewPixels` (`96x96` grayscale), and auto-orients the wrist entry border to the canonical `right` edge (`x = 95`) with contrast normalization.
- Features: `vs_ai` (game + scoreboard + `CameraViewfinder`), `practice` (live per-class confidence + `CameraViewfinder`), `history` (Hive match records + stats).
- ADR 0001 Riverpod (+ addendum: reference-counted shared camera/interpreter lifecycle across vs_ai & practice); ADR 0002 Hive; ADR 0003 Live viewfinder (`ClassificationResult.previewPixels`) & wrist-border orientation normalization.

## apps/event_llm_wiki
- Runtime: `flutter_litert_lm ^0.3.0` running `litert-community/Gemma3-1B-IT` (`.litertlm`, dynamic_int4, ~529 MB, 4096 ctx), **downloaded at runtime on the mobile device**, gated → needs `HF_TOKEN` via `--dart-define` or the in-app confirmation dialog (ADR 0001).
- RAG: no embeddings — plain-Dart weighted lexical scorer (title×3, speaker×2, track/day×1, abstract×1), top-3 talks from bundled `assets/agenda.json` (ADR 0002). Citations = retrieved talks computed *before* generation.
- State: Riverpod; documented exception — chat view model is **not** `.autoDispose` (expensive engine reload, single consumer) (ADR 0003).
- Persistence: Hive for chat history only (ADR 0004).
- Download: one-shot, non-resumable, Wi-Fi-gated (`NetworkConnectivityService` + Android `ConnectivityManager` `TRANSPORT_WIFI`), user-confirmed (`confirmModelDownloadDialog`), stream to `.part`, min-size check, atomic rename (ADR 0005).
- Features: `agenda` (list/detail), `setup` (Wi-Fi check + user confirmation + model download), `chat` (streaming, citation chips). Android-only target; iOS inference explicitly unverified.

## apps/a2ui_snap_sell
- **Concept ("Snap & Sell")**: User snaps/picks a photo of an item to sell (`car` ICE/EV, `motorcycle`, `phone`) on a single fixed entry screen (`EntryScreen`). All subsequent screens (`selling_step_1_detected`, `selling_step_2_followup`, `selling_step_3_preview`, `selling_step_4_published`, `selling_unsupported`) are dynamically generated as A2UI `v0.9` surfaces by a Python ADK agent.
- **Shared Contract (`contracts/`)**: `snap_sell_catalog.json` (`https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`: 12 `BasicCatalog` components + 5 custom components: `StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`) and 5 schema-validated JSON examples (`contracts/examples/0.9/01..05`).
- **Python Agent (`agent/`)**: Scaffolded via `agents-cli scaffold create snap-sell-agent --agent adk --deployment-target cloud_run --prototype` (`google-agents-cli ~= 1.11.0`, `google-adk >= 2.12.0`, `a2ui-agent-sdk == 0.9.0`). Preserves `MODEL = "gemini-3.8-flash"`, `root_agent`, `app = App(root_agent=root_agent, name="app")`, 4 deterministic ADK tools in `app/tools.py` (`record_detected_item`, `validate_listing_fields`, `extract_odometer_reading`, `estimate_price_and_build_preview`), and built-in `A2aAgentExecutor(force_new_version=False)` with custom A2A/A2UI part converters in `app/app_utils/a2a.py` (ADR 0001, ADR 0002, ADR 0005, ADR 0006).
- **Flutter Mobile Client (`mobile/`)**: Uses `genui: ^0.10.4` + `genui_a2a: ^0.10.1` + `image_picker: ^1.2.4` behind `SellingAgentRepository` and `ImageCaptureRepository` (1280px/Q80 + 1.5MB cap). Implements the 5 custom catalog items with two-way `DataContext` binding (`DataContextBindingExt`) and `UserActionEvent` dispatch (ADR 0003, ADR 0004).
