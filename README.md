# Flutter AI

A showcase of mobile applications built with Flutter and Artificial Intelligence, exploring how on-device language models, real-time computer vision, local vector search, dynamic generative interfaces, and collaborative multi-agent teams transform the mobile user experience.

Every project in this repository solves a practical problem with a distinct AI paradigm—from running a coordinated team of travel agents completely offline on a phone to generating custom user interfaces on the fly from a single camera photo.

---

## Showcase Applications

### Pocket Squad — On-Device Multi-Agent Travel Concierge

Pocket Squad turns a smartphone into a private travel agency powered by a team of four collaborating AI agents running offline with Google's Agent Development Kit and Gemma 4. A conversational **Coordinator Agent** chats naturally with the traveler to gather the destination, trip duration, and target budget, then hands the mission over to a sequential team of specialists: a **Scout Agent** that designs a day-by-day sightseeing route, a **Budget Auditor Agent** that calculates exact multi-currency costs and contingency buffers, and a **Concierge Agent** that curates local gastronomy, insider logistics, and packing tips while saving the complete dossier to the local Trips Vault.

[Explore the Pocket Squad Documentation →](apps/adk_pocket_squad/README.md)

```mermaid
flowchart LR
    Traveler["Traveler Request"] --> Coord["Coordinator Agent\nConversational Intake"]
    Coord -->|"Delegates Mission"| Scout["Scout Agent\nDay-by-Day Itinerary"]
    Scout -->|"Draft Route"| Auditor["Budget Auditor Agent\nMulti-Currency Audit"]
    Auditor -->|"Audited Budget"| Concierge["Concierge Agent\nLocal Guide & Packing"]
    Concierge --> Vault["Saved Trips Vault"]
```

| Curated Mission Presets | Multi-Turn Conversational Intake | Day-by-Day Sightseeing Route | Audited Multi-Currency Budget |
| :---: | :---: | :---: | :---: |
| <img src="images/adk_pocket/01-squad-mission-ready.jpeg" alt="Squad Mission Ready" width="220" /> | <img src="images/adk_pocket/08-coordinator-conversational-intake.jpeg" alt="Conversational Intake" width="220" /> | <img src="images/adk_pocket/03-scout-agent-day1-itinerary.jpeg" alt="Scout Agent Itinerary" width="220" /> | <img src="images/adk_pocket/05-budget-auditor-math-breakdown.jpeg" alt="Budget Auditor Breakdown" width="220" /> |

---

### StudyGemma — Offline PDF Study Companion with Vector RAG

StudyGemma is a private, offline study assistant that lets students and researchers import PDF textbooks, lecture notes, and papers directly onto their phone. The app extracts and chunks document pages in the background, indexes them into a local SQLite vector database using EmbeddingGemma 2, and uses Gemma 4 to answer questions across languages while citing the exact source document and page number for every claim.

[Explore the StudyGemma Documentation →](apps/rag_study_gemma/README.md)

[![Watch on YouTube Shorts](https://img.shields.io/badge/YouTube_Shorts-Watch_StudyGemma_Demo-FF0000?style=for-the-badge&logo=youtube&logoColor=white)](https://youtube.com/shorts/Aj-404FV_dE)

| Live Video Walkthrough | On-Device Vector Indexing | Grounded Summary in English | Cross-Lingual Q&A with Citations |
| :---: | :---: | :---: | :---: |
| [![StudyGemma Live Demo](images/rag_study/00-study-gemma-demo.gif)](https://youtube.com/shorts/Aj-404FV_dE) | <img src="images/rag_study/03-library-indexing-progress.jpeg" alt="Indexing Progress" width="220" /> | <img src="images/rag_study/05-chat-summary-en.jpeg" alt="Grounded Summary" width="220" /> | <img src="images/rag_study/06-chat-crosslingual-es-citations.jpeg" alt="Cross-Lingual Q&A" width="220" /> |

---

### Snap & Sell — Generative UI Marketplace Assistant

Most apps ship every screen ahead of time. Snap & Sell ships only a camera: you photograph a car, motorcycle or phone, and an AI agent decides which questions to ask and builds each next screen for that item, rendered natively in Flutter through [A2UI](https://a2ui.org).

```mermaid
flowchart LR
    U["📷 Photo"] --> A{{"🤖 Agent decides<br/>what to ask"}}
    A --> S["🧩 Screen for this item"]
    S --> R["📱 Native Flutter UI"]
    R -- "answers" --> A
```

It is built two ways so you can compare them on the same photo:

| | Who decides | Who writes the screen | Per photo |
| --- | --- | --- | --- |
| [**Snap & Sell Express**](apps/a2ui/snap_sell_express/README.md) | Gemini | Gemini, in A2UI Express | ~5–9 s |
| [**Snap & Sell · Jev**](apps/a2ui/snap_sell_jev/README.md) | [Jev](https://docs.typesafe.ai), with a probability per choice | Code | ~2–3 s |

[Compare the two variants →](apps/a2ui/README.md)

| Item Recognition Surface | Conditional Odometer Request | Dynamic Price Range | Final Listing Confirmation |
| :---: | :---: | :---: | :---: |
| <img src="images/a2ui/01-step1-detected-car.jpeg" alt="Detected Car" width="220" /> | <img src="images/a2ui/03-step2-odometer-followup.jpeg" alt="Odometer Follow-up" width="220" /> | <img src="images/a2ui/04-step3-price-range-preview.jpeg" alt="Price Range Preview" width="220" /> | <img src="images/a2ui/06-step4-published.jpeg" alt="Published Confirmation" width="220" /> |

---

### Event Gemma — Offline Conference Guide & Assistant

Event Gemma is an offline companion for technology conferences. Attendees can browse the schedule by day and track, inspect speaker profiles, and chat in Spanish or English with an on-device Gemma 3 assistant that searches the conference catalog to recommend talks, summarize keynotes, and link directly to the referenced sessions without needing an internet connection.

[Explore the Event Gemma Documentation →](apps/event_gemma/README.md)

| Conference Schedule & Tracks | Session & Speaker Details | Keynote Recommendations | Topic Search with Session Links |
| :---: | :---: | :---: | :---: |
| <img src="images/event_gemma/01-agenda-list.jpeg" alt="Agenda View" width="220" /> | <img src="images/event_gemma/02-session-details.jpeg" alt="Session Details" width="220" /> | <img src="images/event_gemma/06-chat-keynotes-citations-en.jpeg" alt="Keynotes Response" width="220" /> | <img src="images/event_gemma/07-chat-topic-grounding-citations.jpeg" alt="Topic Grounding" width="220" /> |

---

### RPS Live — Real-Time Hand Gesture Game

RPS Live brings real-time computer vision to mobile gaming. Using the phone's front or rear camera, an on-device convolutional neural network classifies hand gestures in real time so players can challenge an AI opponent in a countdown match, test live gesture confidence bars in practice mode, and track their match history. The repository also includes the Jupyter notebook used to train and export the custom vision model.

[Explore the RPS Live Documentation →](apps/rps_live/README.md) · [Explore the Model Training Notebook →](notebooks/README.md)

| Live Match — Paper | Live Match — Rock | Real-Time Practice Meters | Match History & Scoreboard |
| :---: | :---: | :---: | :---: |
| <img src="images/rsp_live/01-vs-ai-paper.jpeg" alt="Detecting Paper" width="220" /> | <img src="images/rsp_live/02-vs-ai-rock.jpeg" alt="Detecting Rock" width="220" /> | <img src="images/rsp_live/04-practice-scissors.jpeg" alt="Practice Mode" width="220" /> | <img src="images/rsp_live/06-match-history.jpeg" alt="Match History" width="220" /> |

---

## AI, Agentic & Generative UI Ecosystem

These applications are built on top of Google's mobile AI, Multi-Agent, and Generative UI ecosystem for Flutter and Python:

| Library / Model | Focus Area | Showcase App | Role in the Experience |
| :--- | :--- | :--- | :--- |
| [**`flutter_adk`**](https://pub.dev/packages/flutter_adk) | Multi-Agent UI & Orchestration | `adk_pocket_squad` | Provides the multi-agent chat controller, live workflow stepper, shared state inspector, tool telemetry cards, and embedded ADK Studio. |
| [**`adk_dart`**](https://pub.dev/packages/adk_dart) | Multi-Agent Core Runtime | `adk_pocket_squad` | Powers on-device hierarchical and sequential agents, deterministic function tools, agent handoffs, and local or LAN model bridges. |
| [**`google-adk`**](https://google.github.io/adk-docs/) | Cloud Agent Orchestration | `snap_sell_express`, `snap_sell_jev` | Orchestrates multimodal Gemini agents on Vertex AI and Cloud Run. |
| [**`flutter_edge_ai`**](https://pub.dev/packages/flutter_edge_ai) | On-Device Edge AI Core | `adk_pocket_squad`, `rag_study_gemma`, `event_gemma` | Unified Flutter SDK for managing local language model sessions and streaming responses on mobile. |
| [**`flutter_edge_ai_litertlm`**](https://pub.dev/packages/flutter_edge_ai_litertlm) | On-Device LLM Runtime | `adk_pocket_squad`, `rag_study_gemma`, `event_gemma` | Runs Gemma 4 and Gemma 3 models directly on the device via Google AI Edge LiteRT-LM. |
| [**`flutter_edge_ai_embeddings`**](https://pub.dev/packages/flutter_edge_ai_embeddings) | On-Device Text Embeddings | `rag_study_gemma` | Generates dense semantic vector embeddings locally using EmbeddingGemma 2. |
| [**`flutter_edge_ai_rag`**](https://pub.dev/packages/flutter_edge_ai_rag) | On-Device RAG Pipeline | `rag_study_gemma` | Handles document chunking, context assembly, and grounded retrieval-augmented generation. |
| [**`flutter_edge_ai_sqlite`**](https://pub.dev/packages/flutter_edge_ai_sqlite) | Local Vector Database | `rag_study_gemma` | Stores and queries vector embeddings offline using SQLite and `sqlite-vec`. |
| [**`a2ui_flutter`**](https://pub.dev/packages/a2ui_flutter) | Generative UI (A2UI 1.0) | `snap_sell_express`, `snap_sell_jev` | Renders A2UI v1.0 surfaces natively and routes actions, errors and agent function calls back to the agent. |
| [**`a2ui_core`**](https://pub.dev/packages/a2ui_core) & [**`a2ui-agent-sdk`**](https://pypi.org/project/a2ui-agent-sdk/) | Agent-to-UI Protocol | `snap_sell_express`, `snap_sell_jev` | Defines the shared component catalog and schema contract between the AI agent and the Flutter client. |
| [**`typesafe-sdk`**](https://pypi.org/project/typesafe-sdk/) (Jev) | Decision Model for UI | `snap_sell_jev` | Answers yes/no, choice and score questions about photos and form data with calibrated probabilities; code turns them into UI decisions. |
| [**`flutter_litert`**](https://pub.dev/packages/flutter_litert) | On-Device Computer Vision | `rps_live` | Executes custom TensorFlow Lite / LiteRT neural networks on mobile hardware accelerators. |

### Official References

- [Google Agent Development Kit Documentation](https://google.github.io/adk-docs/) · [`flutter_adk`](https://pub.dev/packages/flutter_adk) · [`adk_dart`](https://pub.dev/packages/adk_dart)
- [Google AI Edge & LiteRT Overview](https://ai.google.dev/edge/litert) · [`flutter_edge_ai`](https://pub.dev/packages/flutter_edge_ai) · [`flutter_litert`](https://pub.dev/packages/flutter_litert)
- [Google Gemma Open Models](https://ai.google.dev/gemma)
- [`a2ui-agent-sdk`](https://pypi.org/project/a2ui-agent-sdk/)
- [A2UI 1.0 for Flutter](https://flutter.dev/blog/a2ui-launch) · [`a2ui_flutter`](https://pub.dev/packages/a2ui_flutter) · [A2UI Express](https://a2ui.org/concepts/inference-formats/)

---

## Running the Applications

Each project under `apps/` is a standalone Flutter application and can be launched directly from its folder:

```bash
cd apps/adk_pocket_squad   # or rps_live, event_gemma, rag_study_gemma, a2ui/snap_sell_express/mobile, a2ui/snap_sell_jev/mobile
flutter pub get
flutter run
```
