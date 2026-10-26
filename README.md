# Flutter AI

A collection of five standalone Flutter apps demonstrating **on-device Edge AI**, **Vector RAG**, **Multi-Agent Systems (ADK)**, and **Generative UI (GenUI + A2UI)** on mobile, plus the training notebook for the custom vision model.

Each app under `apps/` is an independent Flutter project with its own `pubspec.yaml` and `doc/adr/` Architecture Decision Records, sharing a consistent Clean Architecture (`domain` / `data` / `ui`), Riverpod state management, single DI composition root, and offline fake-based TDD suite.

## Apps Overview

| App | AI / Agentic Stack | Key Libraries | Verified Status | Docs |
| :--- | :--- | :--- | :--- | :--- |
| [**`rps_live`**](apps/rps_live/README.md) | On-Device Vision CNN (`.tflite` · `XNNPACK` / `Metal`) | `flutter_litert`, `camera`, `flutter_riverpod`, `hive` | 77 tests · Android 15 | [README](apps/rps_live/README.md) |
| [**`event_gemma`**](apps/event_gemma/README.md) | On-Device **Gemma 3 1B IT** + Bilingual Lexical RAG | `flutter_edge_ai`, `flutter_edge_ai_litertlm`, `flutter_riverpod`, `hive` | 147 tests · Android 15 | [README](apps/event_gemma/README.md) |
| [**`a2ui_snap_sell`**](apps/a2ui_snap_sell/README.md) | **Python ADK** (`gemini-3.8-flash`) + **Flutter GenUI** (`A2UI v0.9`) | `google-adk`, `a2ui-agent-sdk`, `genui`, `genui_a2a`, `a2ui_core` | 20 pytest + 43 Flutter tests · Cloud Run | [README](apps/a2ui_snap_sell/README.md) |
| [**`rag_study_gemma`**](apps/rag_study_gemma/README.md) | On-Device PDF Vector RAG (**EmbeddingGemma 2** + `sqlite-vec` + **Gemma 4 E2B IT**) | `flutter_edge_ai_litertlm`, `flutter_edge_ai_embeddings`, `flutter_edge_ai_rag`, `flutter_edge_ai_sqlite` | 78 tests · Android 15 ([Demo Video](https://youtube.com/shorts/Aj-404FV_dE)) | [README](apps/rag_study_gemma/README.md) |
| [**`adk_pocket_squad`**](apps/adk_pocket_squad/README.md) | On-Device 4-Agent **ADK MAS** (`Coordinator` + 3-Agent `SequentialAgent` + **Gemma 4 E2B IT**) | `flutter_adk`, `adk_dart`, `flutter_edge_ai`, `flutter_edge_ai_litertlm`, `flutter_riverpod` | 36 tests · Android 15 (`~0.8 GB` RAM) | [README](apps/adk_pocket_squad/README.md) |

---

### 1. [`apps/rps_live`](apps/rps_live/README.md) — Rock/Paper/Scissors Live (LiteRT Vision)

Real-time hand-gesture classifier and "You vs. AI" game running a custom 29K-parameter `.tflite` CNN on-device (`XNNPACK` / `Metal`) with a plugin-free `96x96` BMP viewfinder and wrist-border orientation normalization.
- **Key Libraries**: [`flutter_litert`](https://pub.dev/packages/flutter_litert) (`^3.8.0`), [`camera`](https://pub.dev/packages/camera) (`^0.12.1`), [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) (`^3.4.3`), [`hive`](https://pub.dev/packages/hive) (`^2.2.3`) · **Docs**: [`apps/rps_live/README.md`](apps/rps_live/README.md)

| You vs. AI — Paper (`100%`) | Practice Mode — Scissors (`94%`) | Persistent Match History |
| :---: | :---: | :---: |
| <img src="images/rsp_live/01-vs-ai-paper.jpeg" alt="You vs. AI detecting Paper" width="220" /> | <img src="images/rsp_live/04-practice-scissors.jpeg" alt="Practice Mode detecting Scissors" width="220" /> | <img src="images/rsp_live/06-match-history.jpeg" alt="Persistent Match History" width="220" /> |

### 2. [`apps/event_gemma`](apps/event_gemma/README.md) — Event Gemma (Gemma 3 1B + Lexical RAG)

Offline conference agenda assistant powered by on-device **Gemma 3 1B IT** (`flutter_edge_ai_litertlm`) and a bilingual (Spanish/English) lexical RAG engine with deterministic talk citations.
- **Key Libraries**: [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) (`^2.5.1`), [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm) (`^1.17.0`), [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) (`^3.4.3`), [`hive`](https://pub.dev/packages/hive) (`^2.2.3`) · **Docs**: [`apps/event_gemma/README.md`](apps/event_gemma/README.md)

| Agenda & Track Filters | Session Details | Grounded Chat & Citations |
| :---: | :---: | :---: |
| <img src="images/event_gemma/01-agenda-list.jpeg" alt="Event Gemma Agenda View" width="220" /> | <img src="images/event_gemma/02-session-details.jpeg" alt="Event Gemma Session Details" width="220" /> | <img src="images/event_gemma/07-chat-topic-grounding-citations.jpeg" alt="Gemma 3 Grounded Topic Query" width="220" /> |

### 3. [`apps/a2ui_snap_sell`](apps/a2ui_snap_sell/README.md) — Snap & Sell (Python ADK + Flutter GenUI + A2UI v0.9)

Client/server generative UI marketplace assistant where a Python ADK agent (`gemini-3.8-flash` on Cloud Run) inspects item photos and streams dynamic A2UI v0.9 surfaces (`DetectedItemCard`, `PhotoRequest`, `PriceRange`, `ListingPreview`) to Flutter GenUI.
- **Key Libraries**: [`google-adk`](https://google.github.io/adk-docs/) (`>=2.12.0`), [`a2ui-agent-sdk`](https://pypi.org/project/a2ui-agent-sdk/) (`>=0.9.0`), [`genui`](https://pub.dev/packages/genui) (`^0.10.4`), [`genui_a2a`](https://pub.dev/packages/genui_a2a) (`^0.10.1`), [`a2ui_core`](https://pub.dev/packages/a2ui_core) (`v0.9`) · **Docs**: [`apps/a2ui_snap_sell/README.md`](apps/a2ui_snap_sell/README.md)

| Step 1 — Detected Item | Step 2 — Odometer Follow-Up | Step 3 — Price Range & Preview |
| :---: | :---: | :---: |
| <img src="images/a2ui/01-step1-detected-car.jpeg" alt="Step 1 Detected Car" width="220" /> | <img src="images/a2ui/03-step2-odometer-followup.jpeg" alt="Step 2 Odometer Follow-up" width="220" /> | <img src="images/a2ui/04-step3-price-range-preview.jpeg" alt="Step 3 Price Range Preview" width="220" /> |

### 4. [`apps/rag_study_gemma`](apps/rag_study_gemma/README.md) — StudyGemma (PDF Vector RAG + EmbeddingGemma 2 + SQLite `vec0` + Gemma 4 E2B IT)

100% offline PDF study companion combining **EmbeddingGemma 2** (`270M`, 768-dim), native **SQLite `sqlite-vec` (`vec0`)**, and **Gemma 4 E2B IT** (`2.58 GB`, CPU `mmap`) for background PDF ingestion and cross-lingual Q&A with `[Doc, p. N]` citations.
- **Key Libraries**: [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) (`^2.5.1`), [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm) (`^1.17.0`), [`flutter_edge_ai_embeddings`](https://pub.dev/packages/flutter_edge_ai_embeddings) (`^2.3.2`), [`flutter_edge_ai_rag`](https://pub.dev/packages/flutter_edge_ai_rag) (`^1.1.2`), [`flutter_edge_ai_sqlite`](https://pub.dev/packages/flutter_edge_ai_sqlite) (`^2.1.1`) · **Docs**: [`apps/rag_study_gemma/README.md`](apps/rag_study_gemma/README.md)

| Live Demo ([YouTube Shorts](https://youtube.com/shorts/Aj-404FV_dE)) | 4-Stage PDF Vector Indexing | Cross-Lingual Q&A & Citations |
| :---: | :---: | :---: |
| [![StudyGemma Live Demo](images/rag_study/00-study-gemma-demo.gif)](https://youtube.com/shorts/Aj-404FV_dE) | <img src="images/rag_study/03-library-indexing-progress.jpeg" alt="4-Stage Indexing Progress" width="220" /> | <img src="images/rag_study/06-chat-crosslingual-es-citations.jpeg" alt="Cross-Lingual Spanish Q&A" width="220" /> |

### 5. [`apps/adk_pocket_squad`](apps/adk_pocket_squad/README.md) — Pocket Squad (On-Device Multi-Agent Concierge with `flutter_adk` + Gemma 4 E2B IT)

100% offline Hierarchical + Sequential Multi-Agent System (`CoordinatorAgent` → `ScoutAgent` → `BudgetAuditorAgent` → `ConciergeAgent`) built with `flutter_adk`, `adk_dart`, and a single shared **Gemma 4 E2B IT** runtime (`~0.8 GB` resident RAM via CPU `mmap`).
- **Key Libraries**: [`flutter_adk`](https://pub.dev/packages/flutter_adk) (`^2026.10.23`), [`adk_dart`](https://pub.dev/packages/adk_dart) (`^2026.10.23`), [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) (`^2.5.1`), [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm) (`^1.17.0`), [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) (`^3.0.3`) · **Docs**: [`apps/adk_pocket_squad/README.md`](apps/adk_pocket_squad/README.md)

| Conversational Intake (`AutoFlow`) | BudgetAuditor Deterministic Math | Pipeline Inspector & Tool Calls |
| :---: | :---: | :---: |
| <img src="images/adk_pocket/08-coordinator-conversational-intake.jpeg" alt="Conversational Intake" width="220" /> | <img src="images/adk_pocket/05-budget-auditor-math-breakdown.jpeg" alt="Budget Auditor Breakdown" width="220" /> | <img src="images/adk_pocket/07-pipeline-state-and-tool-calls.jpeg" alt="Pipeline Inspector and Tool Calls" width="220" /> |

---

## Core AI, ADK, GenUI & Edge AI Libraries

| Library | Version | Ecosystem / Layer | Used In | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| [**`flutter_adk`**](https://pub.dev/packages/flutter_adk) | `^2026.10.23` | Agent Development Kit (Flutter UI) | `adk_pocket_squad` | Turnkey multi-agent chat, workflow stepper, state inspector, tool telemetry cards, and embedded `AdkDevStudioView`. |
| [**`adk_dart`**](https://pub.dev/packages/adk_dart) | `^2026.10.23` | Agent Development Kit (Dart Core) | `adk_pocket_squad` | On-device `LlmAgent`, `SequentialAgent`, `FunctionTool`, `BaseLlm`, `LiteLlm`, `InMemoryRunner`, and `transfer_to_agent`. |
| [**`google-adk`**](https://google.github.io/adk-docs/) | `>=2.12.0` | Agent Development Kit (Python) | `a2ui_snap_sell` | Cloud Run / Vertex AI agent orchestration with Gemini 3.8 Flash and BigQuery/OpenTelemetry instrumentation. |
| [**`flutter_edge_ai`**](https://pub.dev/packages/flutter_edge_ai) | `^2.5.1` | On-Device Edge AI Core | `event_gemma`, `rag_study_gemma`, `adk_pocket_squad` | Unified Flutter SDK for on-device LLM inference, session management, and streaming completions. |
| [**`flutter_edge_ai_litertlm`**](https://pub.dev/packages/flutter_edge_ai_litertlm) | `^1.17.0` | LiteRT-LM Runtime | `event_gemma`, `rag_study_gemma`, `adk_pocket_squad` | Native `.litertlm` model execution for **Gemma 4 E2B IT** (`2.58 GB`) and **Gemma 3 1B IT** with CPU `mmap` & GPU delegates. |
| [**`flutter_edge_ai_embeddings`**](https://pub.dev/packages/flutter_edge_ai_embeddings) | `^2.3.2` | On-Device Embeddings | `rag_study_gemma` | Local 768-dim dense vector generation with **EmbeddingGemma 2 (Embeddings 2.0, 270M)**. |
| [**`flutter_edge_ai_rag`**](https://pub.dev/packages/flutter_edge_ai_rag) | `^1.1.2` | On-Device Vector RAG | `rag_study_gemma` | Structure-aware sliding-window chunking and local Retrieval-Augmented Generation pipeline. |
| [**`flutter_edge_ai_sqlite`**](https://pub.dev/packages/flutter_edge_ai_sqlite) | `^2.1.1` | Vector Database (`sqlite-vec`) | `rag_study_gemma` | Native SQLite + `vec0` virtual tables (`SqliteVectorStoreProvider`) for offline Top-K cosine similarity search. |
| [**`flutter_litert`**](https://pub.dev/packages/flutter_litert) | `^3.8.0` | LiteRT (TFLite) Vision | `rps_live` | Real-time `.tflite` CNN gesture classification with `XNNPACK` (Android) and `Metal` (iOS) hardware delegates. |
| [**`genui`**](https://pub.dev/packages/genui) & [**`genui_a2a`**](https://pub.dev/packages/genui_a2a) | `^0.10.4` / `^0.10.1` | Flutter GenUI + A2A | `a2ui_snap_sell` | Dynamic AI-generated UI surface rendering and Agent-to-Agent (A2A) streaming client in Flutter. |
| [**`a2ui_core`**](https://pub.dev/packages/a2ui_core) & [**`a2ui-agent-sdk`**](https://pypi.org/project/a2ui-agent-sdk/) | `v0.9` | A2UI Protocol | `a2ui_snap_sell` | Shared Agent-to-UI v0.9 JSON Schema component catalog and surface diffing between Python ADK and Flutter. |
| [**`flutter_riverpod`**](https://pub.dev/packages/flutter_riverpod) | `^3.0.3` / `^3.4.3` | State & DI | All 5 apps | Reactive `Notifier` / `AsyncNotifier` ViewModels and single DI composition root per app. |

---

## Repository Layout

```text
flutter-ai/
├── notebooks/               # CNN training & LiteRT export notebook (see notebooks/README.md)
├── images/                  # Diagrams & on-device screenshots (rsp_live, event_gemma, a2ui, rag_study, adk_pocket)
├── apps/
│   ├── rps_live/            # App 1: LiteRT gesture classifier game
│   ├── event_gemma/         # App 2: Gemma 3 1B lexical RAG conference assistant
│   ├── a2ui_snap_sell/      # App 3: Python ADK + Flutter GenUI + A2UI v0.9 marketplace assistant
│   ├── rag_study_gemma/     # App 4: PDF Vector RAG study companion (EmbeddingGemma 2 + sqlite-vec + Gemma 4 E2B IT)
│   └── adk_pocket_squad/    # App 5: On-device multi-agent travel concierge (flutter_adk + Gemma 4 E2B IT)
├── context/memory/          # LLM Wiki persistent project memory & session logs
├── .agents/skills/          # Flutter/Dart & Google Cloud agent skills
└── .claude/plugins/         # senior-dev & senior-dev-flutter orchestration plugins
```

## Working in This Repo

Each app is run and tested independently from its own directory:

```bash
# App 1: RPS Live
cd apps/rps_live && flutter pub get && flutter analyze && flutter test

# App 2: Event Gemma
cd apps/event_gemma && flutter pub get && flutter analyze && flutter test

# App 3: Snap & Sell (Python ADK Agent + Flutter Mobile Client)
cd apps/a2ui_snap_sell/agent && uv run pytest tests/unit tests/integration && agents-cli lint
cd apps/a2ui_snap_sell/mobile && flutter pub get && flutter analyze && flutter test

# App 4: StudyGemma (On-Device PDF Vector RAG Study Companion)
cd apps/rag_study_gemma && flutter pub get && flutter analyze && flutter test

# App 5: Pocket Squad (100% On-Device Multi-Agent Travel & Budget Concierge)
cd apps/adk_pocket_squad && flutter pub get && flutter analyze && flutter test
```

## References & Official Documentation

- **Agent Development Kit (ADK)**:
  - [Google Agent Development Kit (ADK) Documentation](https://google.github.io/adk-docs/)
  - [`flutter_adk` on pub.dev](https://pub.dev/packages/flutter_adk) & [`adk_dart` on pub.dev](https://pub.dev/packages/adk_dart)
- **On-Device Edge AI & Vector RAG (`flutter_edge_ai` Suite)**:
  - [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) · [`flutter_edge_ai_litertlm`](https://pub.dev/packages/flutter_edge_ai_litertlm) · [`flutter_edge_ai_embeddings`](https://pub.dev/packages/flutter_edge_ai_embeddings) · [`flutter_edge_ai_rag`](https://pub.dev/packages/flutter_edge_ai_rag) · [`flutter_edge_ai_sqlite`](https://pub.dev/packages/flutter_edge_ai_sqlite)
- **Flutter GenUI & A2UI / A2A Protocols**:
  - [`genui` on pub.dev](https://pub.dev/packages/genui) & [`genui_a2a` on pub.dev](https://pub.dev/packages/genui_a2a)
  - [`a2ui_core` on pub.dev](https://pub.dev/packages/a2ui_core) & [`a2ui-agent-sdk` on PyPI](https://pypi.org/project/a2ui-agent-sdk/)
- **LiteRT & Gemma Open Models**:
  - [Google AI Edge & LiteRT / LiteRT-LM Documentation](https://ai.google.dev/edge/litert) · [`flutter_litert` on pub.dev](https://pub.dev/packages/flutter_litert)
  - [Google Gemma Open Models (Gemma 4, Gemma 3 & EmbeddingGemma 2)](https://ai.google.dev/gemma)
