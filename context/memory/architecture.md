# Architecture Digest (living — update in place)

Monorepo of **independent** Flutter apps (no shared package) + training notebooks.
Full rationale lives in each app's `doc/adr/`; this page is the digest.

## Repo layout
```text
flutter-ai/
├── notebooks/                 # RPS CNN training (Kaggle drgfreeman/rockpaperscissors)
├── apps/rps_live/             # App 1 — live-camera RPS classifier game (LiteRT)
├── apps/event_gemma/          # App 2 — offline conference wiki + on-device Gemma 3 1B RAG chat
├── apps/a2ui_snap_sell/       # App 3 — "Snap & Sell" dynamic A2UI v0.9 + Flutter GenUI marketplace app (agent/ + mobile/ + contracts/)
├── apps/rag_study_gemma/      # App 4 — "StudyGemma" offline PDF Vector RAG study companion (EmbeddingGemma 2 + SQLite vec0 + Gemma 4 E2B IT)
├── apps/adk_pocket_squad/     # App 5 — "Pocket Squad" 100% on-device Multi-Agent Travel & Budget Concierge (flutter_adk + Gemma 4 E2B IT 2.58 GB)
├── docs/a2ui/                 # Reference docs for ADK A2UI & Flutter GenUI
├── .agents/                   # Antigravity: official flutter/dart + google-agents-cli + a2ui skills + senior-dev/senior-dev-flutter plugins
├── .claude/                   # Claude Code: senior-dev-flutter plugin
└── context/memory/            # this cross-AI LLM Wiki
```

## Shared cross-app pattern
- Layers: `lib/domain/` (models, repo interfaces, use cases) → `lib/data/` (services, repo impls, DTOs, local) → `lib/ui/` (features/<f>/{views,view_models}, core/widgets).
- DI: single composition root `lib/ui/providers/repository_providers.dart`; providers **throw until overridden** in `main.dart`.
- State: `flutter_riverpod ^3.4.3`, manual (non-codegen) `Notifier`/`AsyncNotifier`, view models `.autoDispose` by default.
- Persistence: Hive (`hive` + `hive_flutter`, `hive_generator`/`build_runner` or manual `TypeAdapter`s for DTOs).
- Native/plugin wrappers (camera, LiteRT engine, Edge AI RAG) are thin, deliberately untested pass-through services; everything else is TDD with fakes (`test/support/fakes.dart`), plus `test/regression/` lifecycle tests.

## apps/rps_live
- Model: 29,235-param CNN, input 96x96 grayscale `[0,1]`, softmax order `paper, rock, scissors`. Asset `assets/models/rps_model.tflite` = **float32-I/O mobile export** (not the INT8 ESP32 build).
- Runtime: `flutter_litert ^3.8.0` + `camera ^0.12.1` (defaults to `CameraLensDirection.front` with live `switchCamera()` toggle); `PreprocessFrameUseCase` crops/resizes/grayscales off the UI thread, produces upright/selfie-mirrored `previewPixels` (`96x96` grayscale), and auto-orients the wrist entry border to the canonical `right` edge (`x = 95`) with contrast normalization.
- Features: `vs_ai` (game + scoreboard + `CameraViewfinder`), `practice` (live per-class confidence + `CameraViewfinder`), `history` (Hive match records + stats).
- ADR 0001 Riverpod (+ addendum: reference-counted shared camera/interpreter lifecycle across vs_ai & practice); ADR 0002 Hive; ADR 0003 Live viewfinder (`ClassificationResult.previewPixels`) & wrist-border orientation normalization.

## apps/event_gemma (formerly event_llm_wiki)
- Runtime: `flutter_edge_ai ^2.5.1` + `flutter_edge_ai_litertlm ^1.17.0` (Dart FFI native assets runtime replacing deprecated `flutter_litert_lm`, ADR 0006) running `Gemma3-1B-IT` (`.litertlm`, dynamic_int4, ~529 MB, 4096 ctx), **downloaded at runtime on the mobile device**, gated with public ungated mirror fallback (`lotapa/gemma3-1b-it-int4.litertlm`).
- RAG: bilingual lexical retrieval (`RetrieveRelevantTalksUseCase`) with diacritic stripping (`áàäâ`->`a`, `éèëê`->`e`, `íìïî`->`i`, `óòöô`->`o`, `úùüû`->`u`, `ñ`->`n`), Spanish/English stopwords, domain synonym expansion (`charla`->`talk`, `ponente`->`speaker`, `ia`->`ai/llm`), and general keynote fallback (`talk-001`, `006`, `011`, `016`). Citations = retrieved talks computed *before* generation (ADR 0002, ADR 0007).
- Prompt Grounding: official persona "Event Gemma", dynamic language matching (detects user language, answers in Spanish/English), and prefilled `systemInstruction` in `LitertLmServiceImpl` (ADR 0007).
- State: Riverpod; documented exception — chat view model is **not** `.autoDispose` (expensive engine reload, single consumer) (ADR 0003).
- Persistence: Hive for chat history only (ADR 0004).
- Download: one-shot, non-resumable, Wi-Fi-gated (`NetworkConnectivityService` + Android `ConnectivityManager` `TRANSPORT_WIFI`), user-confirmed (`confirmModelDownloadDialog`), manual redirect resolution stripping `Authorization` on cross-host CDN hops (`us.aws.cdn.hf.co`) with automatic fallback to public ungated `lotapa/gemma3-1b-it-int4.litertlm` mirror on `401`/`403`, buffered `IOSink` stream to `.part`, min-size check, atomic rename (ADR 0005).
- UI/UX Design System: Modern Material 3 tech aesthetic (`lib/ui/core/theme/`): Deep Indigo/Violet primary, luminous Cyan/Teal accents, high-contrast surface containers, Day filter chips (`Day 1` / `Day 2`) + rich talk cards with initials avatars in `agenda`, hero header + speaker profile + "Ask AI" CTA in `talk_detail`, asymmetric bubbles + prompt suggestion pills + pulsing 3-dot generation indicator in `chat`, and hero onboarding card + live Wi-Fi meter in `setup` (ADR 0006). Android-first target.


## apps/a2ui_snap_sell
- **Concept ("Snap & Sell")**: User snaps/picks a photo of an item to sell (`car` ICE/EV, `motorcycle`, `phone`) on a single fixed entry screen (`EntryScreen`). All subsequent screens (`selling_step_1_detected`, `selling_step_2_followup`, `selling_step_3_preview`, `selling_step_4_published`, `selling_unsupported`) are dynamically generated as A2UI `v0.9` surfaces by a Python ADK agent.
- **Shared Contract (`contracts/`)**: `snap_sell_catalog.json` (`https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`: 12 `BasicCatalog` components + 5 custom components: `StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`) and 5 schema-validated JSON examples (`contracts/examples/0.9/01..05`).
- **Python Agent (`agent/`)**: Scaffolded via `agents-cli scaffold create snap-sell-agent --agent adk --deployment-target cloud_run --prototype` (`google-agents-cli ~= 1.11.0`, `google-adk >= 2.12.0`, `a2ui-agent-sdk == 0.9.0`). Preserves `MODEL = "gemini-3.8-flash"`, `root_agent`, `app = App(root_agent=root_agent, name="app")`, 4 deterministic ADK tools in `app/tools.py` (`record_detected_item`, `validate_listing_fields`, `extract_odometer_reading`, `estimate_price_and_build_preview`), and built-in `A2aAgentExecutor(force_new_version=False)` with custom A2A/A2UI part converters in `app/app_utils/a2a.py` (ADR 0001, ADR 0002, ADR 0005, ADR 0006).
- **Flutter Mobile Client (`mobile/`)**: Uses `genui: ^0.10.4` + `genui_a2a: ^0.10.1` + `image_picker: ^1.2.4` behind `SellingAgentRepository` and `ImageCaptureRepository` (1280px/Q80 + 1.5MB cap). Implements the 5 custom catalog items with two-way `DataContext` binding (`DataContextBindingExt`) and `UserActionEvent` dispatch (ADR 0003, ADR 0004).

## apps/rag_study_gemma ("StudyGemma")
- **Concept**: 100% offline, on-device PDF Vector RAG Study Companion. Users import PDFs (`.pdf` only), run an on-device 4-stage RAG ingestion pipeline (`Validate PDF` → `Extract Pages` → `Sliding-Window Chunks` → `EmbeddingGemma 2 + SQLite vec0`), and chat with **StudyGemma** with per-PDF filter chips and clickable `[Doc Title · p. N]` page citations.
- **Dual-Model Runtime & Vector Store (`EdgeAiRagServiceImpl`)**: `flutter_edge_ai ^2.5.1` + `flutter_edge_ai_litertlm ^1.17.0` + `flutter_edge_ai_embeddings ^2.3.2` + `flutter_edge_ai_rag ^1.1.2` + `flutter_edge_ai_sqlite ^2.1.1`. Runs **EmbeddingGemma 2** (`embeddinggemma-2-text-270m.litertlm`, 768-dim, 1024 ctx, embedded SentencePiece tokenizer, profile `'embeddinggemma2-litertlm-text-4410a540ce75-prefix-v1'`) and **Gemma 4 E2B IT** (`gemma-4-E2B-it.litertlm`, 2.58 GB, `ModelType.gemma4`, `PreferredBackend.cpu`, `maxTokens: 2048`) over a single live `RagIndex` (`study_gemma_rag.sqlite` `vec0` virtual table, `FilterSchema` on `doc_id`, `doc_title`, `page_number`, `chunk_index`) (ADR 0001, ADR 0002).
- **PDF Ingestion & Chunking**: `file_picker` (`.pdf` only) + `%PDF-` magic header check + `syncfusion_flutter_pdf` page extraction inside `Isolate.run()` (`PdfExtractorServiceImpl`). `ChunkDocumentUseCase` heals soft PDF margin wraps and splits prose strictly at sentence/newline boundaries (ADR 0002, ADR 0003).
- **State, Persistence & Download**: Riverpod 3.x with non-`autoDispose` `studyChatViewModelProvider`; Hive manual adapters (`StudyDocumentDto` `typeId: 0` with `chunkIds`, `ChatMessageDto` `typeId: 1` with `CitationDto`); sequential two-stage Wi-Fi-gated download (`EmbeddingGemma 2` ~157 MB + `Gemma 4 E2B IT` ~2.58 GB) with optional HF token, cross-host CDN redirect `Authorization` stripping, and ungated mirror fallback (ADR 0004, ADR 0005).

## apps/adk_pocket_squad ("Pocket Squad")
- **Concept**: 100% On-Device Hierarchical + Sequential Multi-Agent Travel & Budget Concierge built with `flutter_adk ^2026.10.23` (`package:adk_dart/adk_core.dart`) and **Gemma 4 E2B IT (`gemma-4-E2B-it.litertlm`, 2.58 GB)**.
- **Multi-Agent Runtime (`OnDeviceLiteRtGemmaLlm extends BaseLlm` + Root `CoordinatorAgent` → `SequentialAgent`)**:
  - `LiteRtChatDriverImpl` loads `gemma-4-E2B-it.litertlm` once on `PreferredBackend.cpu` (`mmap` ~0.8 GB RAM) and serializes turns across the root `coordinator_agent` (`LlmAgent`, `subAgents: <BaseAgent>[pipelineAgent]`) and all 3 specialist sub-agents (`scout_agent` → `budget_auditor_agent` → `concierge_agent`), recreating only the lightweight `InferenceChat` session per turn. Also supports optional `LiteLlm` (Local LAN Ollama / LM Studio).
  - Conversational Intake & `transfer_to_agent` Handoff: `TripIntakeReadiness` evaluates multi-turn user history for explicit **Destination + Duration (days) + Budget** and Spanish/English language detection. When incomplete (e.g. `"Hola"`), `coordinator_agent` chats naturally asking only for missing fields; once all 3 are collected, it invokes ADK's `transfer_to_agent(agent_name: 'pocket_squad_pipeline')`.
  - Authentic LLM vs. `FunctionTool` boundary: `scout_agent` uses 100% native LLM world knowledge (`0` tools → `outputKey: 'itinerary_draft'`); `budget_auditor_agent` calls `calculate_budget_math` (`FunctionTool` for exact arithmetic, 10% buffer, and currency conversion → `outputKey: 'budget_audit'`); `concierge_agent` calls `save_trip_plan` (`FunctionTool` persisting `SavedTrip` to `SharedPreferences` → `outputKey: 'final_concierge_brief'`). (ADR 0001).
- **Wi-Fi `MethodChannel` & UI/UX**: Native Android `MethodChannel('com.jggomez.flutterai.adk_pocket_squad/network')` (`ConnectivityManager` `TRANSPORT_WIFI`) + atomic `.part` download (ADR 0002). Editorial Luxury Travel Concierge 4-tab workspace with 4-step progress (`0. Coordinator` → `1. ScoutAgent` → `2. BudgetAuditor` → `3. Concierge`), `AdkChatView`, `AdkWorkflowGraphView`, `AdkToolInspectorView`, `Trips Vault`, and `AdkDevStudioView` (ADR 0003).

