# Flutter AI

A collection of independent Flutter apps demonstrating on-device and
agentic AI on mobile, plus the notebook used to train one of the models
they use.

Each app under `apps/` is a fully standalone Flutter project (its own
`pubspec.yaml`, no shared package between them). They intentionally share
architectural conventions — a layered `domain` / `data` / `ui` structure,
Riverpod for state, Hive for local persistence, a single dependency
injection composition root, fake-based TDD, and Architecture Decision
Records under each app's `doc/adr/` — so the repo reads as one consistent
system rather than unrelated demos.

## Apps

### `apps/rps_live` — Rock/Paper/Scissors Live

A live-camera hand-gesture classifier turned into a "you vs. the AI" game,
running fully on-device via LiteRT (the current name for the TensorFlow
Lite runtime and file format), with live front/rear camera switching, a
plugin-free `96x96` grayscale BMP viewfinder, and automatic wrist-border
orientation & contrast normalization. See
[`apps/rps_live/README.md`](apps/rps_live/README.md).

Status: built, tested (77 tests, clean analyzer), reviewed, and verified
end-to-end on a physical Android device: OPPO Reno10 5G (`CPH2531`, Android 15 / API 35).

| You vs. AI — Paper (`100%`) | You vs. AI — Rock (`97%`) | Practice Mode — Scissors (`94%`) | Persistent Match History (`18 rounds`) |
| :---: | :---: | :---: | :---: |
| <img src="images/rsp_live/01-vs-ai-paper.jpeg" alt="You vs. AI detecting Paper" width="220" /> | <img src="images/rsp_live/02-vs-ai-rock.jpeg" alt="You vs. AI detecting Rock" width="220" /> | <img src="images/rsp_live/04-practice-scissors.jpeg" alt="Practice Mode detecting Scissors" width="220" /> | <img src="images/rsp_live/06-match-history.jpeg" alt="Persistent Match History" width="220" /> |

### `apps/event_gemma` — Event Gemma

A conference-agenda guide with an on-device chat assistant that answers
questions about the agenda using retrieval-augmented generation, fully
offline, citing the specific talks it used. Runs an on-device Gemma 3 1B model via
`flutter_edge_ai_litertlm`, powered by a high-precision bilingual (Spanish/English)
lexical RAG engine and a modern Material 3 AI/tech design system. See
[`apps/event_gemma/README.md`](apps/event_gemma/README.md).

Status: architecture and implementation complete (147 tests passing, clean
analyzer), bilingual Spanish/English RAG verified on physical Android hardware:
OPPO Reno10 5G (`CPH2531`, Android 15 / API 35) with the Impeller Vulkan engine and dynamic 120Hz display refresh rate.

| Agenda (Day Filters & Badges) | Session Details & Profile | Keynote Query Grounding | Topic Grounding & Citations |
| :---: | :---: | :---: | :---: |
| <img src="images/event_gemma/01-agenda-list.jpeg" alt="Event Gemma Agenda View" width="220" /> | <img src="images/event_gemma/02-session-details.jpeg" alt="Event Gemma Session Details" width="220" /> | <img src="images/event_gemma/06-chat-keynotes-citations-en.jpeg" alt="Gemma 3 On-Device Keynotes Response" width="220" /> | <img src="images/event_gemma/07-chat-topic-grounding-citations.jpeg" alt="Gemma 3 Grounded Topic Query" width="220" /> |

### `apps/a2ui_snap_sell` — Snap & Sell (A2UI v0.9 + Flutter GenUI)

A client/server generative UI marketplace assistant where a mobile user snaps
a photo of an item to sell (ICE/EV car, motorcycle, or phone) on a single fixed
entry screen, and a remote Python ADK agent (Gemini 3.8 Flash on Vertex AI /
Cloud Run) dynamically generates every subsequent screen as A2UI v0.9 surfaces
(`DetectedItemCard`, conditional `PhotoRequest` for damage/odometer,
`PriceRange`, `ListingPreview`, `StepProgress`). See
[`apps/a2ui_snap_sell/README.md`](apps/a2ui_snap_sell/README.md).

Status: built, tested (`agent/`: 20 pytest tests + `agents-cli lint` clean;
`mobile/`: 43 Flutter tests + `flutter analyze` clean), deployed to Cloud Run
(`min-instances=0`, `512Mi` RAM, `1 vCPU` throttled), and verified end-to-end
on a physical Android device.

| Step 1 — Detected (Car) | Step 2 — Odometer Follow-Up | Step 3 — Suggested Price Range | Step 4 — Published Confirmation |
| :---: | :---: | :---: | :---: |
| <img src="images/a2ui/01-step1-detected-car.jpeg" alt="Step 1 Detected Car" width="220" /> | <img src="images/a2ui/03-step2-odometer-followup.jpeg" alt="Step 2 Odometer Follow-up" width="220" /> | <img src="images/a2ui/04-step3-price-range-preview.jpeg" alt="Step 3 Price Range Preview" width="220" /> | <img src="images/a2ui/06-step4-published.jpeg" alt="Step 4 Published Confirmation" width="220" /> |

### `apps/rag_study_gemma` — StudyGemma (PDF Vector RAG + Embeddings 2.0 + SQLite `vec0` + Gemma 4 E2B IT)

A 100% offline, on-device **PDF Vector RAG Study Companion** powered by
**EmbeddingGemma 2 (Embeddings 2.0, 270M, 768-dim)**, **SQLite `sqlite-vec`
(`vec0`)** native vector storage (`flutter_edge_ai_sqlite` +
`flutter_edge_ai_rag`), and **Gemma 4 E2B IT (2.58 GB, Mixed 2/4/8-bit, CPU `mmap`)**
via `flutter_edge_ai_litertlm`. Users import study PDFs (textbooks, lecture notes,
research papers), watch the real-time 4-stage on-device RAG ingestion pipeline
(PDF validation → background isolate page extraction → structure-aware sliding-window
chunking → 768-dim vector indexing in `study_gemma_rag.sqlite`), and chat with StudyGemma
with document-scoped filters and interactive `[Doc Title · p. N]` page citations. See
[`apps/rag_study_gemma/README.md`](apps/rag_study_gemma/README.md).

Status: architecture and full Clean Architecture implementation complete (**78/78
unit, widget, and regression tests passing**; `flutter analyze` clean with 0 issues).
Verified and benchmarked on physical Android hardware: **OPPO Reno10 5G (`CPH2531`, Android 15 / API 35,
MediaTek Dimensity 7050, 8 GB RAM, Arm Mali-G68 MC4 GPU, Impeller Vulkan 120Hz)** with ~9.6s–12.2s prefill and ~7.8–9.0 tokens/sec decode throughput.
[![Watch on YouTube Shorts](https://img.shields.io/badge/YouTube_Shorts-Watch_StudyGemma_Demo-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtube.com/shorts/Aj-404FV_dE)

| Live Walkthrough Demo (Click for YouTube) | 4-Stage Indexing Progress | Grounded Summary (English) | Cross-Lingual Q&A (Spanish) |
| :---: | :---: | :---: | :---: |
| [![StudyGemma Live Demo](images/rag_study/00-study-gemma-demo.gif)](https://youtube.com/shorts/Aj-404FV_dE) | <img src="images/rag_study/03-library-indexing-progress.jpeg" alt="4-Stage Indexing Progress" width="220" /> | <img src="images/rag_study/05-chat-summary-en.jpeg" alt="Grounded Summary in English" width="220" /> | <img src="images/rag_study/06-chat-crosslingual-es-citations.jpeg" alt="Cross-Lingual Spanish Q&A" width="220" /> |

### `apps/adk_pocket_squad` — Pocket Squad (On-Device Multi-Agent Travel & Budget Concierge with `flutter_adk` + Gemma 4 E2B IT)

A 100% offline, on-device **Hierarchical + Sequential Multi-Agent System (MAS)**
travel & budget concierge built with Flutter, **Google's Agent Development Kit (`flutter_adk` + `adk_dart`)**,
and a single shared **Gemma 4 E2B IT (`gemma-4-E2B-it.litertlm`, ~2.58 GB)** runtime via
`flutter_edge_ai` and `flutter_edge_ai_litertlm`. A conversational **CoordinatorAgent** (`AutoFlow`)
chats naturally with the traveler across turns to gather `Destination`, `Days`, and `Budget`, and then
delegates via `transfer_to_agent('pocket_squad_pipeline')` to a 3-agent sequential pipeline (`SingleFlow`):
**ScoutAgent** (`0` tools, designing real day-by-day morning/afternoon/evening sightseeing routes from
native LLM world knowledge) → **BudgetAuditorAgent** (deterministic multi-currency math, 10% contingency,
and budget delta via `calculate_budget_math`) → **ConciergeAgent** (local gastronomy, insider logistics,
packing tips, and automatic **Trips Vault** persistence via `save_trip_plan`). See
[`apps/adk_pocket_squad/README.md`](apps/adk_pocket_squad/README.md).

Status: architecture and Clean Architecture implementation complete (**36/36 unit, multi-agent pipeline, and widget tests passing**; `flutter analyze` clean with 0 issues).
Verified on physical Android hardware: **OPPO Reno10 5G (`CPH2531`, Android 15 / API 35, 8 GB RAM, Impeller Vulkan 120Hz)** with ~0.8 GB resident RAM via CPU `mmap`.

```mermaid
flowchart LR
    User["Traveler Prompt"] --> Coord["0. CoordinatorAgent\n(Multi-Turn Intake · AutoFlow)"]
    Coord -->|"transfer_to_agent"| Scout["1. ScoutAgent\n(World Knowledge · 0 tools)"]
    Scout -->|"itinerary_draft"| Auditor["2. BudgetAuditorAgent\n(calculate_budget_math)"]
    Auditor -->|"budget_audit"| Concierge["3. ConciergeAgent\n(save_trip_plan -> Vault)"]
    Concierge -->|"final_concierge_brief"| UI["Specialist Cards & Trips Vault"]
```

| Squad Mission Ready & Presets | Conversational Multi-Turn Intake | ScoutAgent Day 1 Itinerary | BudgetAuditor Mathematical Audit |
| :---: | :---: | :---: | :---: |
| <img src="images/adk_pocket/01-squad-mission-ready.jpeg" alt="Squad Mission Ready" width="220" /> | <img src="images/adk_pocket/08-coordinator-conversational-intake.jpeg" alt="Conversational Intake" width="220" /> | <img src="images/adk_pocket/03-scout-agent-day1-itinerary.jpeg" alt="ScoutAgent Day 1 Itinerary" width="220" /> | <img src="images/adk_pocket/05-budget-auditor-math-breakdown.jpeg" alt="Budget Auditor Breakdown" width="220" /> |

## AI, ADK & GenUI Ecosystem & References

| AI / Agentic Library | Ecosystem / Layer | Apps Using It | AI Role |
| :--- | :--- | :--- | :--- |
| [**`flutter_adk`**](https://pub.dev/packages/flutter_adk) | Agent Development Kit (Flutter UI) | `adk_pocket_squad` | Multi-agent chat controller, workflow stepper, shared state inspector, tool execution cards, and `AdkDevStudioView`. |
| [**`adk_dart`**](https://pub.dev/packages/adk_dart) | Agent Development Kit (Dart Core) | `adk_pocket_squad` | On-device `LlmAgent`, `SequentialAgent`, `FunctionTool`, `BaseLlm`, `LiteLlm`, `InMemoryRunner`, and `transfer_to_agent`. |
| [**`google-adk`**](https://google.github.io/adk-docs/) | Agent Development Kit (Python) | `a2ui_snap_sell` | Vertex AI / Cloud Run agent orchestration (`gemini-3.8-flash`) with multimodal vision and deterministic tools. |
| [**`flutter_edge_ai`**](https://pub.dev/packages/flutter_edge_ai) | On-Device Edge AI Core | `event_gemma`, `rag_study_gemma`, `adk_pocket_squad` | Unified Flutter SDK for on-device LLM inference, session lifecycle, and streaming token generation. |
| [**`flutter_edge_ai_litertlm`**](https://pub.dev/packages/flutter_edge_ai_litertlm) | LiteRT-LM Runtime | `event_gemma`, `rag_study_gemma`, `adk_pocket_squad` | Native `.litertlm` model execution for **Gemma 4 E2B IT** (`2.58 GB`) and **Gemma 3 1B IT** (`~529 MB`) with CPU `mmap` & GPU delegates. |
| [**`flutter_edge_ai_embeddings`**](https://pub.dev/packages/flutter_edge_ai_embeddings) | On-Device Embeddings | `rag_study_gemma` | Local 768-dim dense vector generation with **EmbeddingGemma 2 (Embeddings 2.0, 270M)**. |
| [**`flutter_edge_ai_rag`**](https://pub.dev/packages/flutter_edge_ai_rag) | On-Device Vector RAG | `rag_study_gemma` | Structure-aware sliding-window chunking and local Retrieval-Augmented Generation pipeline. |
| [**`flutter_edge_ai_sqlite`**](https://pub.dev/packages/flutter_edge_ai_sqlite) | Vector Database (`sqlite-vec`) | `rag_study_gemma` | Native SQLite + `vec0` virtual tables (`SqliteVectorStoreProvider`) for offline Top-K cosine similarity search. |
| [**`flutter_litert`**](https://pub.dev/packages/flutter_litert) | LiteRT (TFLite) Vision | `rps_live` | Real-time `.tflite` CNN gesture classification with `XNNPACK` (Android) and `Metal` (iOS) hardware delegates. |
| [**`genui`**](https://pub.dev/packages/genui) & [**`genui_a2a`**](https://pub.dev/packages/genui_a2a) | Flutter GenUI + A2A | `a2ui_snap_sell` | Dynamic AI-generated UI surface rendering and Agent-to-Agent (A2A) multimodal streaming client. |
| [**`a2ui_core`**](https://pub.dev/packages/a2ui_core) & [**`a2ui-agent-sdk`**](https://pypi.org/project/a2ui-agent-sdk/) | A2UI Protocol | `a2ui_snap_sell` | Shared Agent-to-UI v0.9 JSON Schema component catalog and surface validation between Python ADK and Flutter. |

- **Official Documentation**:
  - [Google Agent Development Kit (ADK)](https://google.github.io/adk-docs/) · [`flutter_adk`](https://pub.dev/packages/flutter_adk) · [`adk_dart`](https://pub.dev/packages/adk_dart)
  - [Google AI Edge & LiteRT / LiteRT-LM](https://ai.google.dev/edge/litert) · [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) · [`flutter_litert`](https://pub.dev/packages/flutter_litert)
  - [Google Gemma Open Models (Gemma 4, Gemma 3 & EmbeddingGemma 2)](https://ai.google.dev/gemma)
  - [Flutter GenUI (`genui`)](https://pub.dev/packages/genui) · [`genui_a2a`](https://pub.dev/packages/genui_a2a) · [`a2ui-agent-sdk`](https://pypi.org/project/a2ui-agent-sdk/)

## Notebooks

[`notebooks/`](notebooks/) contains the training notebook for the
Rock/Paper/Scissors model used by `apps/rps_live`, including the two
separate export paths (microcontroller vs. mobile) it produces. See
[`notebooks/README.md`](notebooks/README.md).

## Repository layout

```text
flutter-ai/
├── notebooks/               # model training notebooks
├── images/                  # architecture diagrams & on-device app screenshots
│   ├── rsp_live/            # RPS Live on-device mobile screenshots
│   ├── event_gemma/         # Event Gemma on-device mobile screenshots
│   ├── a2ui/                # Snap & Sell A2UI interaction diagram & mobile screenshots
│   ├── rag_study/           # StudyGemma on-device mobile screenshots & demo video
│   └── adk_pocket/          # Pocket Squad on-device multi-agent mobile screenshots
├── apps/
│   ├── rps_live/            # app 1: on-device LiteRT gesture classifier game
│   ├── event_gemma/         # app 2: on-device Gemma 3 1B RAG conference assistant
│   ├── a2ui_snap_sell/      # app 3: A2UI v0.9 + Flutter GenUI + ADK marketplace assistant
│   │   ├── agent/           # Python ADK agent (Gemini 3.8 Flash + a2ui-agent-sdk v0.9)
│   │   ├── mobile/          # Flutter GenUI mobile client
│   │   ├── contracts/       # shared A2UI v0.9 JSON Schema catalog & few-shot examples
│   │   └── doc/adr/         # Architecture Decision Records (0001..0006)
│   ├── rag_study_gemma/     # app 4: on-device PDF Vector RAG study companion (EmbeddingGemma 2 + sqlite-vec + Gemma 4 E2B IT)
│   └── adk_pocket_squad/    # app 5: 100% on-device multi-agent travel concierge (flutter_adk + Gemma 4 E2B IT)
├── context/memory/          # LLM Wiki persistent project memory & session logs
├── .agents/skills/          # official Flutter/Dart & Google Cloud agent skills
└── .claude/plugins/         # senior-dev & senior-dev-flutter orchestration plugins
```

## Working in this repo

Each app is run and tested independently from its own directory:

```bash
# App 1: RPS Live
cd apps/rps_live && flutter pub get && flutter test

# App 2: Event Gemma
cd apps/event_gemma && flutter pub get && flutter test

# App 3: Snap & Sell (Python ADK Agent + Flutter Mobile Client)
cd apps/a2ui_snap_sell/agent && uv run pytest tests/unit tests/integration && agents-cli lint
cd apps/a2ui_snap_sell/mobile && flutter pub get && flutter analyze && flutter test

# App 4: StudyGemma (On-Device PDF Vector RAG Study Companion)
cd apps/rag_study_gemma && flutter pub get && flutter analyze && flutter test

# App 5: Pocket Squad (100% On-Device Multi-Agent Travel & Budget Concierge)
cd apps/adk_pocket_squad && flutter pub get && flutter analyze && flutter test
```

See each app's own README for how to run it (including, for
`event_gemma`, `rag_study_gemma`, and `adk_pocket_squad`, the optional HuggingFace
token setup and automatic public mirror fallback, and for `a2ui_snap_sell`, the local ADK server
or Cloud Run configuration).
