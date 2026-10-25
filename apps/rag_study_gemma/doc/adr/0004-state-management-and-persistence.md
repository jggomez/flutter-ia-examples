# 0004. State Management (`flutter_riverpod` 3.x) & Dual-Box Hive Persistence

- **Status**: accepted
- **Date**: 2026-10-24
- **Deciders**: flutter-architect

## Context

**StudyGemma** (`apps/rag_study_gemma`) is the fourth app in the `flutter-ai` monorepo and follows the established layered architecture (`lib/domain/` → `lib/data/` → `lib/ui/`). It coordinates three interactive feature flows:
1. **Setup (`ModelDownloadViewModel`)**: Dual-model readiness check, Wi-Fi verification, and sequential download streaming.
2. **Document Library (`DocumentLibraryViewModel`)**: Listing imported study PDFs, streaming 4-stage PDF ingestion progress (`validating` → `extracting` → `chunking` → `embedding`), and deleting documents.
3. **Study Chat (`StudyChatViewModel`)**: Selecting an optional document filter (`All Documents` vs a specific `StudyDocument`), retrieving top-K cited chunks, streaming grounded responses from `Gemma 3 1B IT`, and persisting conversation history with clickable `[Doc Title — Page N]` citations.

Additionally, StudyGemma must persist two structured application catalogs across restarts (`StudyDocument` library metadata and `ChatMessage` history) while keeping the 768-dim vector embeddings in `study_gemma_rag.sqlite` (ADR 0002).

## Decision

### 1. Riverpod 3.x Manual Providers & Single Composition Root
Use **`flutter_riverpod: ^3.4.3`** with manual (non-codegen) `Notifier` and `AsyncNotifier` declarations. Ephemeral widget-local UI state (such as active navigation tab index, text field controllers, or hovered filter states) uses local `StatefulWidget` + `setState` with mandatory `.dispose()` cleanup.

`lib/ui/providers/repository_providers.dart` is the **single DI composition root** exposing the five core repository providers:
- `modelDownloadRepositoryProvider` (`Provider<ModelDownloadRepository>`)
- `documentIngestionRepositoryProvider` (`Provider<DocumentIngestionRepository>`)
- `ragIndexRepositoryProvider` (`Provider<RagIndexRepository>`)
- `chatEngineRepositoryProvider` (`Provider<ChatEngineRepository>`)
- `chatHistoryRepositoryProvider` (`Provider<ChatHistoryRepository>`)

Each provider throws `UnimplementedError` by default and is overridden in `main.dart`'s root `ProviderScope(overrides: [...])` for production, or in `ProviderContainer` / `ProviderScope` overrides inside `flutter test`.

### 2. Provider Lifecycle & the Non-`autoDispose` `studyChatViewModelProvider` Exception
- `modelDownloadViewModelProvider` and `documentLibraryViewModelProvider` use `.autoDispose` so their state and stream subscriptions clean up automatically when their view unmounts.
- **`studyChatViewModelProvider` is deliberately NOT `.autoDispose`**. Initializing `Gemma 3 1B IT` (~529 MB) and `EmbeddingGemma 2` (~157 MB) plus opening the `study_gemma_rag.sqlite` `RagIndex` is an expensive operation. When a student switches between the **PDF Library** tab and the **Study Chat** tab to inspect a document or upload another lecture note, the loaded LLM session, active conversation state, and `RagIndex` must remain warm in memory for the lifetime of the `ProviderScope`.
- `ChatEngineRepositoryImpl` and `RagIndexRepositoryImpl` delegate to the shared `EdgeAiRagService` singleton with idempotent `initialize()` guards so tab switches never reload native weights or open duplicate SQLite handles.

### 3. Hive Persistence for Document Catalog & Chat History (`typeId: 0` & `typeId: 1`)
Use **`hive: ^2.2.3`** and **`hive_flutter: ^1.1.0`** initialized synchronously in `main.dart` before `runApp()`. `lib/data/local/hive_boxes.dart` is the single registry of box names and type IDs:

| Entity | DTO Class | Hive Box Name | `HiveTypeIds` Constant | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `StudyDocument` | `StudyDocumentDto` | `HiveBoxes.documents` (`'study_documents'`) | `HiveTypeIds.studyDocument = 0` | Persists imported PDF catalog (`id`, `title`, `fileName`, `pageCount`, `chunkCount`, `indexedAt`). Does **not** store raw PDF text or embeddings (those live in `study_gemma_rag.sqlite`). |
| `ChatMessage` | `ChatMessageDto` | `HiveBoxes.chatHistory` (`'study_chat_history'`) | `HiveTypeIds.chatMessage = 1` | Persists chat turns (`id`, `role`, `content`, `createdAt`, and serialized citation metadata: `docId`, `docTitle`, `pageNumber`, `snippet`, `similarityScore`). |

### 4. Model Download State Is Derived from the Filesystem (Never Persisted in Hive)
Consistent with `apps/event_gemma` ADR 0004 and ADR 0005, model readiness is **never** stored as a boolean flag in Hive or `shared_preferences`. `ModelDownloadRepository.checkModelsReady()` always inspects the actual files on disk via `AppStorageService` and `ValidateDownloadedModelsUseCase` so cleared storage or interrupted `.part` downloads self-heal automatically on launch.

## Alternatives Considered

- **Storing Document Catalog Metadata Inside a Custom SQLite Table alongside `vec0`**:
  - *Rejected*: `flutter_edge_ai_sqlite` encapsulates its internal SQLite schema behind `RagIndex`. Opening a second raw `sqlite3` connection to the same `study_gemma_rag.sqlite` file for CRUD catalog queries risks lock contention with `flutter_edge_ai_sqlite`'s internal connection and requires native FFI setup in simple catalog unit tests. Hive provides fast, pure-Dart, synchronous box reads in `flutter test` via `Hive.init(tempDir.path)`.
- **Making `studyChatViewModelProvider` `.autoDispose`**:
  - *Rejected*: Tearing down and reloading a 529 MB LLM and 157 MB embedder on every tab switch between `Documents` and `Study Chat` introduces multi-second stalls and unnecessary native heap churn.

## Consequences

- **Fast Tab Transitions**: Switching between the PDF Library and Study Chat tabs is instantaneous (0ms model reload overhead).
- **Synchronized Deletion**: Deleting a PDF via `DocumentLibraryViewModel.deleteDocument(docId)` removes its vector chunks from `RagIndexRepository` *and* removes its metadata record from `HiveBoxes.documents`, then refreshes the library state and clears any stale document filter in `StudyChatViewModel`.
- **100% Test Isolation**: Every repository and view model can be tested in `flutter test` using in-memory fakes or temporary Hive directories without platform channels.

## Compliance

`flutter-reviewer` checks:
- [ ] No `package:flutter_bloc`, `package:provider`, or `package:signals` imports anywhere under `lib/`.
- [ ] `package:hive` and `package:hive_flutter` are imported **ONLY** under `lib/data/**` and `lib/main.dart`.
- [ ] `lib/data/local/hive_boxes.dart` defines `HiveTypeIds.studyDocument = 0` and `HiveTypeIds.chatMessage = 1` with zero `typeId` collisions.
- [ ] `lib/ui/providers/repository_providers.dart` is the sole composition root, and view models under `lib/ui/features/**/view_models/` depend only on domain repositories/use cases (never `lib/data/**` implementations).
- [ ] `studyChatViewModelProvider` is the only non-`autoDispose` feature view-model provider, backed by regression test coverage verifying that tab switches do not re-initialize the LLM engine.
