# StudyGemma (`rag_study_gemma`) — Architecture & Implementation Plan

> Canonical copy mirrored in [`docs/PLAN.md`](docs/PLAN.md).

**StudyGemma** (`apps/rag_study_gemma`) is App 4 in the `flutter-ai` monorepo: a 100% offline, on-device **PDF Vector RAG Study Companion** built with Flutter, **EmbeddingGemma 2 (Embeddings 2.0)**, **SQLite `sqlite-vec` (`vec0`)** native vector storage, and **Gemma 3 1B IT** via the `flutter_edge_ai` ecosystem.

Users import study PDFs (textbooks, research papers, lecture notes, manuals), watch the real-time on-device RAG ingestion pipeline (**PDF Extraction → Structure-Aware Sliding-Window Chunking → 768-dim EmbeddingGemma 2 Vectorization → SQLite `vec0` Indexing**), and chat with **StudyGemma** to ask grounded questions, generate summaries, or quiz themselves with clickable `[Doc Title — Page N]` citations.

---

## Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | New multi-screen application with 3 primary feature areas: **Setup** (`ModelDownloadScreen` + `ModelDownloadViewModel` for dual-model download + HF token + Wi-Fi gate), **PDF Library & RAG Pipeline** (`DocumentLibraryScreen` + `DocumentLibraryViewModel` with real-time stage progress), and **Study Chat** (`StudyChatScreen` + `StudyChatViewModel` with document filter chips & page citations). | Full multi-screen feature set, view models, and custom Material 3 widgets | **YES (MANDATORY)** |
| **State management (`Riverpod`) contracts changed** | Introduces Riverpod 3.x manual `Notifier`/`AsyncNotifier` contracts across `ModelDownloadViewModel`, `DocumentLibraryViewModel`, and `StudyChatViewModel` (non-`autoDispose` singleton lifecycle for the loaded LLM + `RagIndex` instance), backed by a single DI composition root (`lib/ui/providers/repository_providers.dart`). | New state contracts, provider overrides, and lifecycle invariants | **YES (MANDATORY)** |
| **Navigation routes changed** | New 2-tab adaptive shell (`Documents` / `Study Chat`) with automatic onboarding gate when either `EmbeddingGemma 2` or `Gemma 3 1B IT` is not yet downloaded, plus modal citation sheet and document filter selection. | New navigation state and screen transitions | **YES (MANDATORY)** |
| **Platform channels / native plugins (`pubspec.yaml`) added** | Integrates `flutter_edge_ai` (`^2.5.1`), `flutter_edge_ai_litertlm` (`^1.17.0`), `flutter_edge_ai_embeddings` (`^2.3.2`), `flutter_edge_ai_rag` (`^1.1.2`), `flutter_edge_ai_sqlite` (`^2.1.1` with Dart FFI Native Assets `sqlite-vec`), `file_picker`, `syncfusion_flutter_pdf`, `hive` / `hive_flutter`, `path_provider`, `http`. Plus Android `ConnectivityManager` (`TRANSPORT_WIFI`) platform channel. | Multiple native FFI plugins, SQLite vector store lifecycle, and platform channel | **YES (MANDATORY)** |

---

## 1. Core Technical Stack & Package Versions

Verified against local toolchain (`Flutter 3.47.2` / `Dart 3.13.2`):

| Component | Package / Version | Role in StudyGemma |
| :--- | :--- | :--- |
| **Core AI Orchestrator** | `flutter_edge_ai: ^2.5.1` | Unified facade (`FlutterEdgeAi.initialize`), model installer, active LLM & embedder lifecycle |
| **LiteRT-LM Runtime** | `flutter_edge_ai_litertlm: ^1.17.0` | Runs both **Gemma 3 1B IT** (`LiteRtLmEngine`) and **EmbeddingGemma 2** (`LiteRtEmbeddingBackend`) on NPU/GPU/CPU |
| **Embeddings 2.0** | `flutter_edge_ai_embeddings: ^2.3.2` | `Embedder` contract, `TaskType.retrievalDocument` / `TaskType.retrievalQuery` prefix formatting, `EmbeddingGemmaTokenizers` |
| **RAG Pipeline** | `flutter_edge_ai_rag: ^1.1.2` | `RagIndex`, `RagDocument`, `RetrievalResult`, metadata `FilterSchema` / `EqualsFilter`, cosine similarity (`1 - distance`) |
| **SQLite Vector Store** | `flutter_edge_ai_sqlite: ^2.1.1` | `SqliteVectorStoreProvider` backed by native `sqlite-vec` (`vec0` virtual table) via Dart FFI Native Assets |
| **PDF Selection** | `file_picker: ^10.3.3` | Native OS file picker restricted strictly to `.pdf` (`FileType.custom`, `allowedExtensions: ['pdf']`) |
| **PDF Text Extraction** | `syncfusion_flutter_pdf: ^31.1.19` | 100% pure-Dart page-by-page text extraction (`PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i)`), safe inside `Isolate.run()` and pure-Dart unit tests |
| **Local Metadata & Chat DB** | `hive: ^2.2.3` + `hive_flutter: ^1.1.0` | Persists imported PDF document catalog (`StudyDocumentDto`) and chat history (`ChatMessageDto`) |
| **State Management** | `flutter_riverpod: ^3.4.3` | Manual `Notifier` / `AsyncNotifier` providers with composition root overrides |

---

## 2. On-Device AI Models & Download Flow

### 2.1 Embedding Model — Embeddings 2.0 (`EmbeddingGemma 2`)
- **HuggingFace Repo**: `litert-community/embeddinggemma-2-text-270m-litert-lm` (revision `9be6e8b90982095dc05c2bd162e4b954ee4dbac7`)
- **Artifact**: `embeddinggemma-2-text-270m.litertlm` (**157.0 MB**, ungated)
- **Profile ID**: `'embeddinggemma2-litertlm-text-4410a540ce75-prefix-v1'`
- **Vector Dimension**: **768** (`float32` normalized embeddings)
- **Context Window**: **1024 tokens** (`EmbeddingInputTooLongException` thrown if exceeded; chunker enforces a conservative `<= 220 words` / `<= 1400 chars` ceiling per chunk)
- **Tokenizer**: Embedded inside the `.litertlm` container (no separate `.model` SentencePiece download needed)

### 2.2 Generative Model — `Gemma 4 E2B IT`
- **Primary Ungated Repo**: `litert-community/gemma-4-E2B-it-litert-lm` (`gemma-4-E2B-it.litertlm`, ~2.58 GB, mixed 2/4/8-bit quantization, `ModelType.gemma4`)
- **Runtime Configuration**: Initialized via `FlutterEdgeAi.getActiveModel(maxTokens: 2048, preferredBackend: PreferredBackend.cpu)` so the 1.12 GB embedding table is memory-mapped (`mmap`) directly from storage (~0.8 GB active RAM footprint on XNNPACK CPU without exhausting Mali GPU `mali_gralloc` buffers), and queried with `temperature: 0.3, topK: 40, topP: 0.9, maxOutputTokens: 420, enableThinking: false`.
- **Wi-Fi + HuggingFace Token Onboarding**:
  - Checks active Wi-Fi connection via `NetworkConnectivityService` (`com.jggomez.flutterai.rag_study_gemma/network` channel on Android `ConnectivityManager` `TRANSPORT_WIFI`).
  - Accepts optional HuggingFace Access Token (`hf_...`) via UI input or `--dart-define-from-file=dart_defines.local.json` (`HF_TOKEN`).
  - Handles cross-host CDN redirects (`huggingface.co` → `us.aws.cdn.hf.co`) by stripping the `Authorization` header on redirect hops, streaming to `.part` files, verifying minimum file size, and atomically renaming upon completion.

---

## 3. End-to-End PDF Vector RAG Pipeline

```text
[1. Pick PDF Only] ──► file_picker (.pdf extension + %PDF- magic header validation)
         │
         ▼
[2. Extract Text per Page] ──► Isolate.run() + syncfusion_flutter_pdf
         │                     Returns List<ExtractedPdfPage(pageNumber, text)>
         ▼
[3. Sliding-Window Chunker] ──► ChunkDocumentUseCase (pure Dart, deterministic)
         │                      - Cleans hyphenation & whitespace
         │                      - Target: ~220 words (~300 tokens) per chunk
         │                      - Overlap: 40 words between consecutive chunks
         │                      - Hard cap: 1400 chars (< 512 tokens, safe for 1024-token limit)
         │                      - Emits List<DocumentChunk> with id, docId, docTitle, pageNumber, chunkIndex, text
         ▼
[4. Embeddings 2.0 + SQLite vec0] ──► VectorStoreService / RagIndexRepositoryImpl
         │                            - RagIndex.add(RagDocument(id, content, metadata: {
         │                                'doc_id': docId, 'doc_title': docTitle,
         │                                'page_number': pageNumber, 'chunk_index': chunkIndex
         │                              }))
         │                            - Embeds with TaskType.retrievalDocument (768-dim)
         │                            - Persists into study_gemma_rag.sqlite (vec0 virtual table)
         ▼
[5. Semantic Retrieval + Grounded Gemma 3 Answer]
         ├─► User asks question (optionally filtered to a specific PDF via EqualsFilter('doc_id', selectedDocId))
         ├─► RagIndex.search(query, topK: 4, similarityThreshold: 0.25, filter: ...)
         │     Embeds query with TaskType.retrievalQuery → cosine similarity search in SQLite vec0
         ├─► BuildStudyPromptUseCase:
         │     Constructs bilingual-aware grounded prompt with [Source N | Doc: <title> | Page <p>] blocks
         └─► Gemma 3 1B IT streams grounded response + UI renders interactive [Doc — p. N] CitationChips
```

---

## 4. Clean Architecture & Folder Layout (`apps/rag_study_gemma/lib/`)

```text
lib/
├── main.dart                                   # Sync Hive bootstrap + ProviderScope overrides
├── app.dart                                    # MaterialApp + 2-tab shell (PDF Library / Study Chat) + Setup gate
├── core/
│   └── error/app_exception.dart                # Base AppException hierarchy
├── domain/                                     # 100% pure Dart, zero Flutter/plugin imports
│   ├── models/
│   │   ├── study_document.dart                 # id, title, fileName, pageCount, chunkCount, indexedAt
│   │   ├── extracted_pdf_page.dart             # pageNumber (1-based), text
│   │   ├── document_chunk.dart                 # id, docId, docTitle, pageNumber, chunkIndex, content
│   │   ├── retrieved_chunk.dart                # chunk, similarityScore
│   │   ├── ingestion_progress.dart             # stage (validating/extracting/chunking/embedding/completed/failed), current, total, message
│   │   ├── chat_role.dart                      # user, assistant
│   │   ├── chat_message.dart                   # id, role, content, citations, createdAt, isStreaming
│   │   ├── citation.dart                       # id, docId, docTitle, pageNumber, snippet, similarityScore
│   │   └── model_download_status.dart          # phase (notDownloaded/downloadingEmbedding/downloadingLlm/ready/failed), progress, bytesReceived, totalBytes
│   ├── repositories/
│   │   ├── document_ingestion_repository.dart  # pickPdf, ingestPdfStream, listDocuments, deleteDocument
│   │   ├── rag_index_repository.dart           # initializeIndex, indexChunks, searchSimilarChunks, removeDocumentChunks, dispose
│   │   ├── chat_engine_repository.dart         # isInitialized, initialize, generateResponseStream, resetConversation, dispose
│   │   ├── chat_history_repository.dart        # loadMessages, saveMessage, clearHistory
│   │   └── model_download_repository.dart      # checkModelsReady, isWifiConnected, downloadModelsStream, deleteModels
│   └── use_cases/
│       ├── chunk_document_use_case.dart        # Pure-Dart sliding-window chunker with overlap & token safety cap
│       ├── retrieve_relevant_chunks_use_case.dart # Queries RagIndexRepository + maps to RetrievedChunk & Citation
│       ├── build_study_prompt_use_case.dart    # Bilingual (ES/EN) grounded study prompt builder with page citations
│       └── validate_downloaded_models_use_case.dart # Validates both EmbeddingGemma 2 & Gemma 3 1B IT files on disk
├── data/
│   ├── local/
│   │   └── hive_boxes.dart                     # HiveBoxes.documents, HiveBoxes.chatHistory & HiveTypeIds
│   ├── models/
│   │   ├── study_document_dto.dart             # Hive adapter (typeId: 0)
│   │   └── chat_message_dto.dart               # Hive adapter (typeId: 1)
│   ├── services/                               # Thin plugin wrappers
│   │   ├── pdf_picker_service.dart             # file_picker (.pdf only)
│   │   ├── pdf_extractor_service.dart          # syncfusion_flutter_pdf + %PDF- header verification inside Isolate.run
│   │   ├── edge_ai_rag_service.dart            # ONLY wrapper importing flutter_edge_ai, litertlm, embeddings, rag, sqlite
│   │   ├── app_storage_service.dart            # path_provider paths for models & study_gemma_rag.sqlite
│   │   ├── model_download_service.dart         # HTTP stream downloader with HF token & cross-host CDN redirect handling
│   │   └── network_connectivity_service.dart   # MethodChannel Wi-Fi check
│   └── repositories/
│       ├── document_ingestion_repository_impl.dart
│       ├── rag_index_repository_impl.dart
│       ├── chat_engine_repository_impl.dart
│       ├── chat_history_repository_impl.dart
│       └── model_download_repository_impl.dart
└── ui/
    ├── core/
    │   ├── theme/app_theme.dart                # Material 3 Deep Academic Emerald / Indigo & Teal AI study theme
    │   └── widgets/
    │       ├── citation_chip.dart              # Interactive [Doc Title · p. N] chip opening snippet preview modal
    │       └── ingestion_progress_card.dart    # Visual 4-step RAG pipeline progress indicator
    ├── providers/
    │   └── repository_providers.dart           # Single DI composition root (throws until overridden in main.dart / tests)
    └── features/
        ├── setup/
        │   ├── view_models/model_download_view_model.dart
        │   └── views/model_download_screen.dart
        ├── library/
        │   ├── view_models/document_library_view_model.dart
        │   └── views/document_library_screen.dart
        └── chat/
            ├── view_models/study_chat_view_model.dart
            └── views/study_chat_screen.dart
```

---

## 5. Architecture Decision Records (`apps/rag_study_gemma/doc/adr/`)

1. **`0001-dual-model-litertlm-and-embeddings2.md`**: Selection of `flutter_edge_ai` + `flutter_edge_ai_litertlm` + `flutter_edge_ai_embeddings` running `EmbeddingGemma 2` (`embeddinggemma-2-text-270m.litertlm`, 768-dim) and `Gemma 3 1B IT` (`Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm`), single `FlutterEdgeAi.initialize()` lifecycle.
2. **`0002-sqlite-vec-rag-index-and-chunking.md`**: On-device vector store using `flutter_edge_ai_sqlite` (`SqliteVectorStoreProvider` / `vec0`) + `flutter_edge_ai_rag` (`RagIndex`), `FilterSchema` (`doc_id`, `doc_title`, `page_number`, `chunk_index`), and deterministic sliding-window PDF chunking (`220 words`, `40-word overlap`, `1400-char` cap).
3. **`0003-pdf-ingestion-and-isolate-extraction.md`**: PDF-only validation (`%PDF-` magic bytes + `.pdf` extension), pure-Dart `syncfusion_flutter_pdf` extraction inside `Isolate.run()` to keep 60/120fps UI frame budget.
4. **`0004-state-management-and-persistence.md`**: Riverpod 3.x manual providers, non-`autoDispose` `studyChatViewModelProvider` and single live `RagIndex` instance, Hive persistence for `StudyDocumentDto` catalog and `ChatMessageDto` history.
5. **`0005-dual-model-wifi-download-flow.md`**: Sequential two-stage download (`EmbeddingGemma 2` 157 MB + `Gemma 3 1B IT` 529 MB) gated by Wi-Fi check, optional HuggingFace token with cross-host CDN redirect stripping, and ungated mirror fallback.

---

## 6. Parallel Execution Tracks

### State 1: Upfront Architecture & Scaffolding
| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Arch Track 1** | `flutter-architect` | `apps/rag_study_gemma/doc/adr/0001-*.md` .. `0005-*.md` | Author the 5 ADRs formalizing the dual-model runtime, SQLite `vec0` RAG schema, PDF chunking invariants, Riverpod lifecycle, and Wi-Fi download flow. |

### State 2: Implementation (Parallel Fan-Out — Mode A Disjoint File Partitioning after Base Scaffold)
| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Impl Phase 0 (Foundation & Scaffold)** | `flutter-implementer` | `apps/rag_study_gemma/pubspec.yaml`, `apps/rag_study_gemma/analysis_options.yaml`, `apps/rag_study_gemma/android/**`, `apps/rag_study_gemma/ios/**`, `apps/rag_study_gemma/lib/core/**`, `apps/rag_study_gemma/lib/domain/models/**`, `apps/rag_study_gemma/lib/domain/repositories/**` | Scaffold `apps/rag_study_gemma`, configure `pubspec.yaml` & Android Wi-Fi `MethodChannel` + minSdk 26, and implement all pure-Dart domain models and repository interfaces + exceptions. |
| **Impl Track A (Domain Use Cases + Data Layer + Unit Tests)** | `flutter-implementer` | `apps/rag_study_gemma/lib/domain/use_cases/**`, `apps/rag_study_gemma/lib/data/**`, `apps/rag_study_gemma/test/support/**`, `apps/rag_study_gemma/test/domain/**`, `apps/rag_study_gemma/test/data/**` | Implement `ChunkDocumentUseCase`, `RetrieveRelevantChunksUseCase`, `BuildStudyPromptUseCase`, `ValidateDownloadedModelsUseCase`, Hive DTOs/boxes, thin services (`EdgeAiRagService`, `PdfExtractorService`, `PdfPickerService`, `ModelDownloadService`, `AppStorageService`, `NetworkConnectivityService`), all 5 `RepositoryImpl` classes, fakes, and full unit test suite. |
| **Impl Track B (UI Layer, ViewModels, Theme & Widget Tests)** | `flutter-implementer` | `apps/rag_study_gemma/lib/main.dart`, `apps/rag_study_gemma/lib/app.dart`, `apps/rag_study_gemma/lib/ui/**`, `apps/rag_study_gemma/test/ui/**`, `apps/rag_study_gemma/test/regression/**`, `apps/rag_study_gemma/test/widget_test.dart` | Implement DI composition root (`repository_providers.dart`), Material 3 `AppTheme`, `CitationChip`, `IngestionProgressCard`, `ModelDownloadViewModel`/`Screen`, `DocumentLibraryViewModel`/`Screen`, `StudyChatViewModel`/`Screen`, `app.dart`, `main.dart`, widget tests, and lifecycle regression tests. |

### State 3 & 4: Review & Release Verification (Parallel Fan-Out)
| Track | Subagent | Scope | Verification Gate |
| :--- | :--- | :--- | :--- |
| **Review Track** | `flutter-reviewer` | `apps/rag_study_gemma/lib/**`, `apps/rag_study_gemma/test/**` | 60/120fps frame budget audit (PDF extraction & chunking off UI thread), `.dispose()` controller & `RagIndex` leak audit, `BuildContext` async gap checks, accessibility semantics, ADR compliance. |
| **Release Track** | `flutter-release-engineer` | `apps/rag_study_gemma/pubspec.yaml`, `apps/rag_study_gemma/android/**`, `apps/rag_study_gemma/ios/**`, `.gitignore` | Verify Android `minSdk >= 26`, Native Assets (`sqlite3` / `sqlite-vec`) build readiness, `dart_defines.local.json` gitignore hygiene, `flutter analyze` (`0 issues`), and `flutter test` (`exit code 0`). |

---

## 7. Verification & Completion Checklist
- [x] `context/memory/MEMORY.md` restored at State 0
- [x] `apps/rag_study_gemma/docs/PLAN.md` and `apps/rag_study_gemma/PLAN.md` authored on disk
- [x] `flutter-architect` invoked for State 1 ADR authoring (`doc/adr/0001..0005`)
- [x] `flutter-implementer` tracks completed with TDD unit, widget, and regression tests (`63/63` passing)
- [x] `flutter-reviewer` (`APPROVED`) and `flutter-release-engineer` (`APPROVED`) passed with `0` analyzer issues and `100%` passing tests
- [x] `context/memory/` (`MEMORY.md`, `architecture.md`, `conventions.md`, `log/2026-10-24.md`) updated at State 5
