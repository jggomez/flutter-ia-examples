# event_llm_wiki — architecture & implementation plan

"Event LLM-Wiki": a browsable conference-agenda "wiki" plus a single-thread
chat assistant answering questions about the agenda using fully offline,
on-device RAG. This document is the hand-off from the architecture phase
(this file + `doc/adr/`) to the `flutter-implementer` TDD phase.

This is app 2 of a multi-app repo. App 1, `apps/rps_live`, is fully built
and reviewed; every ADR below explicitly derives from and contrasts with
its `apps/rps_live/doc/adr/` counterpart so the repo reads as one
consistent system with intentional, documented deviations, not accidental
drift.

## Architecture decisions (see `doc/adr/` for full rationale)

- **Inference runtime + model**: `flutter_litert_lm` (`^0.3.0`) running
  `litert-community/Gemma3-1B-IT`, `.litertlm`, `dynamic_int4`, ~529 MB,
  4096-token context, downloaded at runtime (not bundled). See
  [`doc/adr/0001-llm-runtime-model-selection.md`](doc/adr/0001-llm-runtime-model-selection.md)
  — this ADR also records exactly how the real installed package's API
  surface was confirmed against the initial assumed shape, and where they
  differ (`sendMessageStream`'s delta-not-cumulative `LiteLmMessage.text`
  semantics).
- **RAG retrieval**: plain-Dart weighted lexical/keyword scoring over the
  bundled `assets/agenda.json` — no embeddings, no vector index. See
  [`doc/adr/0002-rag-lexical-retrieval.md`](doc/adr/0002-rag-lexical-retrieval.md).
- **State management**: `flutter_riverpod` (v3.x), manual providers, no
  codegen — inherited from `apps/rps_live`'s ADR 0001, with one documented
  exception (`chatViewModelProvider` is NOT `.autoDispose`). See
  [`doc/adr/0003-state-management-riverpod.md`](doc/adr/0003-state-management-riverpod.md).
- **Persistence**: Hive, for chat history only — inherited from
  `apps/rps_live`'s ADR 0002. Model-download progress is deliberately NOT
  persisted (file existence on disk is the source of truth). See
  [`doc/adr/0004-persistence-hive-chat-history.md`](doc/adr/0004-persistence-hive-chat-history.md).
- **Model download**: one-shot, non-resumable, min-size-checked, atomic
  rename. See
  [`doc/adr/0005-model-download-flow.md`](doc/adr/0005-model-download-flow.md).
- **Testability boundary**: `AgendaRepository`, `ChatEngineRepository`,
  `ChatHistoryRepository`, `ModelDownloadRepository` (all under
  `lib/domain/repositories/`) are the only seams the rest of the app
  depends on. Real implementations live in `lib/data/repositories/`;
  tests inject fakes via `ProviderContainer(overrides: [...])`
  (`lib/ui/providers/repository_providers.dart`). No real `.litertlm`
  model, real ~529 MB download, real network call, or real asset bundle is
  ever required to run `flutter test` — `data/services/litert_lm_service.dart`
  is the one deliberately-untested native-engine wrapper, exactly mirroring
  how `apps/rps_live` isolates `camera`/`flutter_litert` behind services.

## Folder layout (`lib/`)

```text
lib/
├── main.dart                # sync Hive bootstrap only (no async model-download gate)
├── app.dart                 # MaterialApp + 2-tab shell (Agenda / Chat)
├── core/
│   └── error/app_exception.dart  # AppException base type (same contract as rps_live)
├── domain/                       # plain Dart, zero Flutter/plugin imports
│   ├── models/
│   │   ├── talk.dart, speaker.dart, conference_day.dart, conference_track.dart
│   │   ├── chat_role.dart, chat_message.dart, citation.dart
│   │   ├── retrieved_talk.dart              # use-case output (talk, score)
│   │   └── model_download_status.dart       # phase: notDownloaded/downloading/ready/failed
│   ├── repositories/        # abstract interfaces + typed exceptions (extend AppException)
│   │   ├── agenda_repository.dart           # AgendaLoadException, TalkNotFoundException
│   │   ├── chat_engine_repository.dart      # ModelLoadException, InferenceException
│   │   ├── chat_history_repository.dart     # ChatPersistenceException
│   │   └── model_download_repository.dart   # ModelDownloadException
│   └── use_cases/            # callable classes, VerbPhraseUseCase.call(...)
│       ├── retrieve_relevant_talks_use_case.dart
│       ├── build_chat_prompt_use_case.dart
│       └── validate_downloaded_model_use_case.dart
├── data/
│   ├── models/chat_message_dto.dart (+.g.dart)   # @HiveType(typeId: 0)
│   ├── services/              # one thin wrapper per plugin
│   │   ├── agenda_asset_service.dart        # rootBundle.loadString
│   │   ├── app_storage_service.dart         # path_provider -> model file path
│   │   ├── model_download_service.dart      # streamed http GET + progress
│   │   └── litert_lm_service.dart           # ONLY file importing package:flutter_litert_lm
│   ├── repositories/          # XRepositoryImpl implements XRepository
│   │   ├── agenda_repository_impl.dart
│   │   ├── chat_history_repository_impl.dart
│   │   ├── model_download_repository_impl.dart
│   │   └── chat_engine_repository_impl.dart
│   └── local/hive_boxes.dart   # HiveBoxes.chatHistory, HiveTypeIds.chatMessageDto = 0
└── ui/
    ├── core/widgets/citation_chip.dart, core/theme/
    ├── providers/repository_providers.dart   # composition root: 4 Providers, overridden in main.dart/tests
    └── features/
        ├── agenda/{view_models,views}/       # AgendaListViewModel + TalkDetailViewModel.family, .autoDispose
        ├── setup/{view_models,views}/        # ModelDownloadViewModel, .autoDispose
        └── chat/{view_models,views}/         # ChatViewModel — deliberately NOT .autoDispose (see ADR 0003)

assets/agenda.json   # bundled & committed — 20 talks, 2 days x 2 tracks, authored during architecture phase
```

Every file above already exists as either a real, structural artifact
(domain models, `assets/agenda.json`, `ChatMessageDto` + its generated
`.g.dart` adapter, `hive_boxes.dart`, the four repository interfaces + typed
exceptions, `ui/providers/repository_providers.dart`) or a stub (data
services/repository impls, use cases, view models, screens — all with
`throw UnimplementedError()` bodies and a doc comment pointing at the phase
below that fills them in). `flutter pub get`, `dart run build_runner build`,
and `flutter analyze` all succeed against this skeleton today (zero
analyzer errors — only expected `unused_field`/`unused_import` warnings from
stub bodies, which clear up phase by phase as real logic replaces
`UnimplementedError()`).

## Implementation phase breakdown (for flutter-implementer, TDD)

1. **Domain models + `assets/agenda.json` content** — already done during
   the architecture phase (`lib/domain/models/**`, 20 talks across 2 days x
   2 tracks in `assets/agenda.json`). `flutter-implementer`'s phase 1 is
   just "verify/adjust" — re-read the bundled JSON against `Talk`'s actual
   fields and confirm nothing needs to change before building on top of it.
2. **`RetrieveRelevantTalksUseCase` + `BuildChatPromptUseCase`**
   (`domain/use_cases/`) — pure Dart, TDD first with exhaustive synthetic
   `Talk` fixtures (see `doc/adr/0002-rag-lexical-retrieval.md` for the
   exact scoring/tie-break algorithm and the "no matching talk" prompt
   requirement). No Flutter/plugin imports; fastest, highest-value tests
   to write first since `ChatViewModel` and both on-device checkpoints in
   phases 7-8 depend on these being correct.
3. **`ValidateDownloadedModelUseCase`** (`domain/use_cases/`) — a pure
   function over a file size; pick a concrete `minValidSizeBytes` threshold
   (see that class's doc comment) and test the boundary.
4. **Repository interfaces + typed exceptions + `test/support/fakes.dart`**
   — the four interfaces under `domain/repositories/` already exist (with
   their typed exceptions extending `AppException`); write the four fakes
   (`FakeAgendaRepository`, `FakeChatEngineRepository`,
   `FakeChatHistoryRepository`, `FakeModelDownloadRepository`) in
   `test/support/fakes.dart` alongside whichever phase first needs one —
   they don't all need to land in a single commit.
5. **`AgendaAssetService` + `AgendaRepositoryImpl`**
   (`data/services/agenda_asset_service.dart`,
   `data/repositories/agenda_repository_impl.dart`) — real
   `rootBundle.loadString` + JSON parsing into `List<Talk>`, cached after
   first read; test with a fake string-loader returning canned JSON (no
   real asset bundle).
6. **`ChatMessageDto` (+ codegen) + `HiveBoxes` + `ChatHistoryRepositoryImpl`**
   — the DTO, its generated `.g.dart` adapter, and `HiveBoxes` already
   exist (architecture phase); `flutter-implementer`'s phase 6 is mainly
   `ChatHistoryRepositoryImpl` (`data/repositories/chat_history_repository_impl.dart`),
   which re-joins `citedTalkIds` against `AgendaRepository` — see
   `doc/adr/0004-persistence-hive-chat-history.md`. Test against a real
   tempdir Hive box (`Hive.init(tempDir)`) plus a `FakeAgendaRepository` —
   no platform channels involved.
7. **`AppStorageService` + `ModelDownloadService` + `ModelDownloadRepositoryImpl`**
   (`data/services/app_storage_service.dart`,
   `data/services/model_download_service.dart`,
   `data/repositories/model_download_repository_impl.dart`) — test against
   a fake byte-stream/filesystem (see
   `doc/adr/0005-model-download-flow.md`'s non-resumable, atomic-rename
   flow). **ON-DEVICE CHECKPOINT A**: wire into a minimal debug screen, run
   on the connected Android device , download
   the real ~529 MB model over real network/storage — confirm progress
   events arrive, the `.part` file appears then disappears, and the final
   model file passes `ValidateDownloadedModelUseCase`.
8. **`LitertLmService`** (thin, deliberately untested — see its doc
   comment) **+ `ChatEngineRepositoryImpl`** (idempotent init guard, stream
   pass-through, dispose safety — NOT reference counting, see
   `doc/adr/0003-state-management-riverpod.md`) against a
   `FakeLitertLmService`. Confirm the exact `LiteLmBackend`/engine API
   against the installed `flutter_litert_lm` version one more time
   immediately before wiring the real calls (package versions can drift
   between the architecture phase and this phase). **ON-DEVICE CHECKPOINT
   B (most critical)**: load the real downloaded model, run a real prompt
   through the engine on-device — confirm load time, memory pressure,
   backend selection (CPU per ADR 0001), and that streaming deltas arrive
   and concatenate into coherent text.
9. **View models** (composition root already exists —
   `ui/providers/repository_providers.dart` — plus the 4 view models:
   `AgendaListViewModel`, `TalkDetailViewModel`, `ModelDownloadViewModel`,
   `ChatViewModel`) via `ProviderContainer(overrides: [...])`. Write the
   **chat-engine-lifecycle regression test here, test-first**: asserts the
   fake engine's `create()`/`initialize()` is called at most once across a
   tab-away/tab-back cycle, given `chatViewModelProvider`'s non-
   `.autoDispose` exception (mirrors `apps/rps_live`'s
   `test/regression/classifier_lifecycle_regression_test.dart`, but proving
   the opposite property: NOT re-initializing, since there is no
   reference-counted shared resource here to protect against a
   multi-consumer race).
10. **UI screens** (`AgendaListScreen`, `TalkDetailScreen`,
    `ModelSetupScreen`, `ChatTabRoot`, `ChatScreen`, `CitationChip`) —
    widget tests per screen against `ProviderScope(overrides: [...])` with
    fakes. **ON-DEVICE CHECKPOINT C**: run the real app end-to-end on the
    connected device as each screen lands, not only at the end.
11. **Wiring**: `main.dart` (construct the real services/repositories,
    override the four providers), `app.dart` (already scaffolded — verify
    the 2-tab shell still matches once real screens replace the stubs).
12. **Final on-device verification pass** (Android only) per this
    checklist:
    - Fresh-install download flow: progress advances; force-quit
      mid-download + relaunch discards the stale `.part` and retries
      cleanly; a completed download survives relaunch and skips straight to
      Chat (no re-download, no re-validation).
    - A question matching a seeded talk streams token-by-token with a
      correct citation chip navigating to the right `TalkDetailScreen`.
    - A question with no agenda match gets an honest "not in this agenda"
      answer with no citation chips.
    - A natural follow-up question stays coherent (validates the engine's
      own multi-turn history — this app does no manual history
      re-injection beyond what the engine's own conversation session
      retains).
    - Force-close/relaunch reloads Hive chat history without
      re-downloading or re-validating the model.
    - Backgrounding/foregrounding mid-generation doesn't crash.
    - iOS: recorded as explicitly unverified (see
      `doc/adr/0001-llm-runtime-model-selection.md`'s iOS note) — not
      silently skipped.

## Non-goals

- Multi-thread/concurrent chat (single thread only).
- Embeddings-based RAG (see ADR 0002).
- Working iOS inference today (see ADR 0001's iOS note — the plugin needs a
  separate, non-trivial native-framework build step this plan does not
  budget for).
- In-app agenda editing/sync — `assets/agenda.json` is bundled and
  read-only for the lifetime of this plan.
- Resumable or checksummed downloads (see ADR 0005).
- Manual re-injection of chat history into the model beyond the engine's
  own conversation-session retention.
- A "reset conversation" action.
- Full-text search on the Agenda tab (browsing/grouping only).
- Speaker photos, bookmarking, notifications, or maps.
- Web/desktop support (Android + iOS only, per `flutter create`'s
  `--platforms=android,ios`).
- Chat analytics/telemetry.

## Verified against the real environment during the architecture phase

- `flutter pub get` succeeds with `flutter_litert_lm: ^0.3.0` resolved
  (alongside `flutter_riverpod ^3.4.3`, `hive ^2.2.3`, `hive_flutter ^1.1.0`,
  `path_provider ^2.1.6`, `http ^1.2.2`, dev deps `hive_generator ^2.0.1` +
  `build_runner ^2.4.13` — same versions as `apps/rps_live` where shared).
- `dart run build_runner build --delete-conflicting-outputs` succeeds and
  generates `lib/data/models/chat_message_dto.g.dart`.
- `flutter analyze` reports zero errors against the full skeleton (only
  expected `unused_field`/`unused_import` warnings from stub bodies — see
  "Folder layout" above).

---

## On-Device Wi-Fi Detection & User Confirmation Gate Pass (2026-10-21)

### Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | Modifies `ModelSetupScreen`, `ModelDownloadViewModel`, `ModelDownloadRepository`, `ModelDownloadRepositoryImpl`, `ModelDownloadService`, `main.dart`, and introduces `NetworkConnectivityService` (`lib/data/services/network_connectivity_service.dart`). | Setup UI + domain/data model download pipeline | **YES (MANDATORY)** |
| **State management / domain contracts changed** | Adds `Future<bool> isWifiConnected()` and optional `String? authToken` override to `ModelDownloadRepository` / `ModelDownloadViewModel`, and enforces Wi-Fi connectivity + explicit user confirmation dialog before downloading the ~529 MB `.litertlm` model on the mobile device. | Updates `ModelDownloadRepository` contract & ADR 0005 | **YES (MANDATORY)** |
| **Navigation routes (`GoRouter`) changed** | Unchanged (2-tab `NavigationBar` in `app.dart`). | None | No |
| **Platform channels / native permissions changed** | Adds `<uses-permission android:name="android.permission.INTERNET"/>` and `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>` in `android/app/src/main/AndroidManifest.xml` and a lightweight `MethodChannel('com.jggomez.flutterai.event_llm_wiki/connectivity')` in `MainActivity.kt` querying `ConnectivityManager` (`NetworkCapabilities.TRANSPORT_WIFI`). | Native Android connectivity check + permissions | **YES (MANDATORY)** |

### Requirements & Design Summary

1. **Strictly On-Device Download (Never Downloaded on PC)**:
   - The ~529 MB `Gemma3-1B-IT` `.litertlm` model is never downloaded on the host PC or bundled in the APK. It is downloaded exclusively on-demand on the mobile device into `getApplicationSupportDirectory()`.
2. **Wi-Fi Connectivity Detection (`NetworkConnectivityService`)**:
   - `NetworkConnectivityService` (`lib/data/services/network_connectivity_service.dart`) checks whether the mobile device has an active Wi-Fi transport via `MethodChannel('com.jggomez.flutterai.event_llm_wiki/connectivity')` (`isWifiConnected`), backed by Android's `ConnectivityManager` + `NetworkCapabilities.TRANSPORT_WIFI` in `MainActivity.kt`.
   - `ModelDownloadRepositoryImpl.download()` verifies `await _networkConnectivityService.isWifiConnected()` before initiating the HTTP stream; if Wi-Fi is not active, it immediately emits `ModelDownloadStatus(phase: ModelDownloadPhase.failed, errorMessage: 'Wi-Fi connection required to download the ~529 MB model on this device. Please connect to Wi-Fi and try again.')`.
3. **Explicit User Confirmation Dialog on `ModelSetupScreen`**:
   - Tapping `Download model (~529 MB)` (or `Retry download`) first checks Wi-Fi status and opens a confirmation `AlertDialog` (`ValueKey('confirmModelDownloadDialog')`) showing:
     - Model details (`Gemma 3 1B-IT · ~529 MB · On-device offline RAG`).
     - Live Wi-Fi status indicator (blocking confirmation if Wi-Fi is disconnected).
     - Optional `HuggingFace Token (HF_TOKEN)` input field (used when `--dart-define=HF_TOKEN=...` was not provided at build time, since `litert-community/Gemma3-1B-IT` is gated on HuggingFace).
      - `Cancel` (`ValueKey('cancelDownloadDialogButton')`) and `Download on Wi-Fi` (`ValueKey('confirmDownloadDialogButton')`) actions.
4. **HuggingFace CDN Cross-Host Redirect Handling & Public Mirror Fallback (`ModelDownloadServiceImpl`)**:
   - Manual redirect resolution (`request.followRedirects = false`, up to 6 hops) attaches `Authorization: Bearer <token>` only to the origin host (`huggingface.co`) and strips `Authorization` when redirected (`302`) to pre-signed CDN hosts (`us.aws.cdn.hf.co`).
   - If the gated `litert-community/Gemma3-1B-IT` URL returns HTTP `401` or `403`, `ModelDownloadServiceImpl` automatically falls back to the public ungated `Gemma3-1B-IT` int4 `.litertlm` mirror (`https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/gemma3-1b-it-int4.litertlm`).

### Parallel Execution Tracks (Mode A — Disjoint File Partitioning)

| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Track 1 — Architecture & ADR 0005 Update** | `flutter-architect` | `doc/adr/0005-model-download-flow.md` | Record the Wi-Fi connectivity requirement (`NetworkConnectivityService`) and mandatory user confirmation gate in ADR 0005. |
| **Track 2 — Full-Stack Implementation & TDD** | `flutter-implementer` | `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/**/MainActivity.kt`, `lib/data/services/network_connectivity_service.dart`, `lib/data/services/model_download_service.dart`, `lib/domain/repositories/model_download_repository.dart`, `lib/data/repositories/model_download_repository_impl.dart`, `lib/ui/features/setup/view_models/model_download_view_model.dart`, `lib/ui/features/setup/views/model_setup_screen.dart`, `lib/main.dart`, `test/**` | Implement `NetworkConnectivityService` + Android `ConnectivityManager` Wi-Fi check, `ModelDownloadRepository.isWifiConnected()`, optional runtime `authToken` pass-through, manual HuggingFace redirect header stripping + ungated mirror fallback, and the `ModelSetupScreen` Wi-Fi confirmation dialog with unit and widget tests. |

### Verification Status (Completed 2026-10-21)
- **Architecture ADR**: [`doc/adr/0005-model-download-flow.md`](doc/adr/0005-model-download-flow.md) (`ACCEPTED` with 2026-10-21 Wi-Fi, confirmation, redirect header stripping & public mirror fallback addendum).
- **Static Analysis & Tests**: `flutter analyze` (`0 issues`), `flutter test` (`125/125 passing`).
- **Review & Release Verdicts**: `flutter-reviewer` (`APPROVED`), `flutter-release-engineer` (`APPROVED`).

---

## Migration to `flutter_edge_ai_litertlm` & Complete UI/UX Redesign Pass (2026-10-21)

### Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | Complete visual redesign of `AgendaListScreen`, `TalkDetailScreen`, `ChatScreen`, `ModelSetupScreen`, `CitationChip`, and new design system in `lib/ui/core/theme/`. | App-wide UX/UI overhaul across all 4 screens | **YES (MANDATORY)** |
| **State management / domain contracts changed** | Updates `LitertLmService` implementation to wrap `flutter_edge_ai_litertlm` (`LiteRtLmEngine` + `FlutterEdgeAi.getActiveModel`) while maintaining the identical `Stream<String> sendMessageStream(prompt)` delta contract so domain/repositories stay 100% decoupled. | Native runtime engine replacement behind existing abstraction | **YES (MANDATORY)** |
| **Navigation routes (`GoRouter`) changed** | Unchanged (2-tab navigation shell with enriched animated transitions & navigation styling). | None | No |
| **Platform channels / native plugins changed** | Replaces deprecated `flutter_litert_lm: ^0.3.0` with `flutter_edge_ai: ^2.5.1` and `flutter_edge_ai_litertlm: ^1.17.0` (Dart FFI native assets). | Upgrades native runtime to the community standard (640+ stars, 5.4k+ monthly downloads) | **YES (MANDATORY)** |

### Architectural Design & Requirements

1. **Native Engine Replacement (`flutter_edge_ai_litertlm`)**:
   - Swap `flutter_litert_lm` for `flutter_edge_ai: ^2.5.1` + `flutter_edge_ai_litertlm: ^1.17.0` in `pubspec.yaml`.
   - In `LitertLmServiceImpl` (`lib/data/services/litert_lm_service.dart`):
     - Initialize `FlutterEdgeAi.initialize(inferenceEngines: [const LiteRtLmEngine(backendFallback: true)])`.
     - In `initialize({required String modelPath})`: register/install model using `FlutterEdgeAi.installModel(modelType: ModelType.gemmaIt, fileType: ModelFileType.litertlm).fromFile(modelPath).install()`.
     - In `sendMessageStream(String prompt)`: obtain `model = await FlutterEdgeAi.getActiveModel(maxTokens: 2048)`, create `chat = await model.createChat()`, and stream tokens via `chat.generateChatResponseAsync()`.
     - Preserve delta-streaming semantics (`TextResponse.token`) so `ChatEngineRepositoryImpl` and `ChatViewModel` require zero contract changes.
2. **Design System & Visual Theming (`lib/ui/core/theme/`)**:
   - Modern Material 3 palette with AI/tech aesthetic: deep indigo/violet primary, vibrant cyan/teal accents, high-contrast dark/light elevated card surfaces (`surfaceContainerLow`, `surfaceContainerHigh`), rounded corners (16–20px), subtle outlines.
   - Clean custom typography with legible hierarchy and branded app bar.
3. **Agenda & Talk Detail UI/UX Overhaul**:
   - Day selector chips (`Day 1 · Oct 24` / `Day 2 · Oct 25`) with active indicator pills.
   - Rich talk cards with track badges (`Track A: AI & Systems`, `Track B: Flutter & Mobile`), time chip with clock icon, title, speaker avatars with initials, and chevron indicator.
   - Detailed talk view: hero header, speaker profile card with initials, abstract in an elevated container, and an "Ask AI about this talk" action pre-filling the prompt.
4. **Chat Experience Overhaul**:
   - Modern conversation layout with user bubble gradient and assistant card with spark icon avatar.
   - Quick prompt suggestion pills on empty state ("What talks cover performance?", "Keynote details?", "Day 1 Track A schedule").
   - Typing/streaming indicator with pulsing animated dots.
   - Floating rounded message composer with clear and send buttons.
5. **Model Setup Screen Overhaul**:
   - Modern hero card with animated AI badge and benefit highlights (Offline, Private, Fast).
   - Polished download card with progress percentage, bytes counter, Wi-Fi badge, and smooth progress bar.

### Parallel Execution Tracks (Mode A — Disjoint File Partitioning)

| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Track 1 — Architecture & ADR 0006** | `flutter-architect` | `doc/adr/0006-flutter-edge-ai-litertlm-migration-and-ui-revamp.md` | Formalize ADR 0006 specifying the `flutter_edge_ai_litertlm` migration contract and the UX/UI component hierarchy and design tokens. |
| **Track 2 — Engine Migration & Tests** | `flutter-implementer` | `pubspec.yaml`, `lib/data/services/litert_lm_service.dart`, `lib/main.dart` | Update dependencies in `pubspec.yaml`, implement `LitertLmServiceImpl` with `flutter_edge_ai_litertlm`, update bootstrap, and verify analyzer + existing tests. |
| **Track 3 — UI/UX Overhaul & Theming** | `flutter-implementer` | `lib/app.dart`, `lib/ui/core/theme/**`, `lib/ui/core/widgets/**`, `lib/ui/features/agenda/**`, `lib/ui/features/chat/**`, `lib/ui/features/setup/**`, `test/ui/**` | Implement modern theme, revamped Agenda list/detail, modern Chat interface with prompt pills, and polished Model Setup screen with unit/widget tests. |

### Verification Status (Completed 2026-10-21)
- **Architecture ADR**: [`doc/adr/0006-flutter-edge-ai-litertlm-migration-and-ui-revamp.md`](doc/adr/0006-flutter-edge-ai-litertlm-migration-and-ui-revamp.md) (`ACCEPTED`).
- **Static Analysis & Tests**: `flutter analyze` (`0 issues`), `flutter test` (`139/139 passing`).
- **Review & Release Verdicts**: `flutter-reviewer` (`APPROVED`), `flutter-release-engineer` (`APPROVED`).

---

## RAG Knowledge Enhancement & Multilingual Grounding (Spanish/English) (2026-10-21)

### Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | Modifies `RetrieveRelevantTalksUseCase`, `BuildChatPromptUseCase`, `LitertLmService`/`ChatEngineRepositoryImpl`, and updates test suites. | Core RAG retrieval, prompt grounding, and conversation turn lifecycle | **YES (MANDATORY)** |
| **State management / domain contracts changed** | Enhances `RetrieveRelevantTalksUseCase` with bilingual normalization (Spanish diacritics, Spanish/English synonyms, general agenda query detection) and `BuildChatPromptUseCase` with conference baseline knowledge and language-matching instructions. | Domain use case behavioral enhancement and prompt structure upgrade | **YES (MANDATORY)** |
| **Navigation routes (`GoRouter`) changed** | Unchanged. | None | No |
| **Platform channels / native plugins changed** | Unchanged (`flutter_edge_ai: ^2.5.1` and `flutter_edge_ai_litertlm: ^1.17.0`). | None | No |

### Architectural Design & Requirements

1. **Bilingual & Semantic Lexical Retrieval (`RetrieveRelevantTalksUseCase`)**:
   - Diacritic normalization (`á` -> `a`, `é` -> `e`, `í` -> `i`, `ó` -> `o`, `ú` -> `u`, `ñ` -> `n`) before regex splitting.
   - Spanish + English stopword filtering (strip `de`, `la`, `el`, `que`, `para`, `por`, `con`, `sobre`, `cual`, `hay`, `son`, `dime`, `cuentame`, etc.).
   - Bilingual synonym mapping:
     - `charla`, `charlas`, `sesion`, `sesiones`, `platica`, `platicas` <-> `talk`, `session`
     - `ia`, `inteligencia artificial` <-> `ai`, `llm`, `model`, `inference`
     - `ponente`, `ponentes`, `expositor`, `expositores` <-> `speaker`
     - `horario`, `horarios`, `agenda`, `evento`, `cronograma` <-> `schedule`, `agenda`, `day`
   - **General Agenda Query Detection**: If the query is an overview/general query (e.g. "qué charlas hay", "resumen de las charlas", "what talks are there", "show me the agenda", "tell me about the conference") or if no individual talk has a positive specific score, return a representative set of talks across both days and tracks (or all 20 talk titles) rather than returning an empty list, so the LLM is always provided with the knowledge base.
2. **Language-Aware Grounded Prompting (`BuildChatPromptUseCase`)**:
   - Persona: "You are Event LLM-Wiki, the official AI conference assistant for the On-Device AI Conference 2026."
   - Multilingual instruction: "Detect the language of the user's question and ALWAYS reply in that exact same language (e.g., if the user asks in Spanish, reply in Spanish; if in English, reply in English)."
   - Baseline Conference Knowledge: Include the conference summary (2 days, 2 tracks: Engineering & Product/Design, 20 talks total) and explicit talk details for retrieved talks.
   - Grounding guarantee: Ground all answers in the provided talks and cite talk titles directly.
3. **Clean Generation & Session Lifecycle (`LitertLmServiceImpl`)**:
   - Ensure prompts with updated dynamic context are sent cleanly without accumulating redundant multi-page prompts in native chat history.

### Parallel Execution Tracks (Mode A — Disjoint File Partitioning)

| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Track 1 — Architecture & ADR 0007** | `flutter-architect` | `doc/adr/0007-rag-knowledge-bilingual-retrieval-and-grounding.md` | Author ADR 0007 detailing the bilingual retrieval algorithm, Spanish synonym mapping, fallback conference overview, and multilingual prompt grounding contract. |
| **Track 2 — Domain RAG & Prompting Implementation** | `flutter-implementer` | `lib/domain/use_cases/retrieve_relevant_talks_use_case.dart`, `lib/domain/use_cases/build_chat_prompt_use_case.dart`, `lib/data/services/litert_lm_service.dart`, `test/domain/use_cases/**` | Implement bilingual normalization, synonym mapping, agenda fallback, language-matching prompt grounding, clean session generation, and unit tests. |

### Verification Status (Completed 2026-10-21)
- **Architecture ADR**: [`doc/adr/0007-rag-knowledge-bilingual-retrieval-and-grounding.md`](doc/adr/0007-rag-knowledge-bilingual-retrieval-and-grounding.md) (`ACCEPTED`).
- **Static Analysis & Tests**: `flutter analyze` (`0 issues`), `flutter test` (`147/147 passing`).
- **Review & Implementation**: `flutter-implementer` verified full bilingual RAG pass.

---

## Project Rebranding: `event_llm_wiki` → `event_gemma` (2026-10-21)

### Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | Global package and identifier rename (`event_llm_wiki` → `event_gemma`) across directory, `pubspec.yaml`, app labels, and package imports in `lib/` and `test/`. | Systematic rename without altering business logic | Skip (pure refactor/rebrand) |
| **State management / domain contracts changed** | None. Business logic and Riverpod providers unchanged. | None | No |
| **Navigation routes (`GoRouter`) changed** | None. | None | No |
| **Platform channels / native plugins changed** | Android application ID / namespace update (`com.jggomez.flutterai.event_gemma`), app labels in Android, iOS, macOS, Web, Linux, Windows. | Platform metadata alignment | No |

### Execution Tracks (Mode A — Disjoint File Partitioning)

| Track | Subagent | Owned Files | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Track 1 — Package & Platform Rebranding** | `flutter-implementer` | `apps/event_gemma/pubspec.yaml`, `apps/event_gemma/lib/**`, `apps/event_gemma/test/**`, `apps/event_gemma/android/**`, `apps/event_gemma/ios/**`, `apps/event_gemma/macos/**`, `apps/event_gemma/web/**`, `apps/event_gemma/linux/**`, `apps/event_gemma/windows/**` | Update package name to `event_gemma`, replace all `package:event_llm_wiki` imports with `package:event_gemma`, update app title to "Event Gemma", align Android namespace/appId and platform display names, run `flutter pub get`, `dart analyze`, and `flutter test`. |
| **Track 2 — Documentation & Memory Update** | `flutter-feature-orchestrator` | `apps/event_gemma/README.md`, `README.md`, `context/memory/**` | Update repo-level and app-level documentation, diagrams, paths, and cross-AI handoff logs. |

### Verification & Completion Signoff (2026-10-21)
- [x] Package renamed to `event_gemma` in `pubspec.yaml`
- [x] All 24 test files and library files updated to `package:event_gemma/`
- [x] Android namespace & applicationId set to `com.jggomez.flutterai.event_gemma`
- [x] Android label, iOS display name, and macOS metadata set to "Event Gemma"
- [x] `flutter pub get` exit code 0
- [x] `flutter analyze` exit code 0 (No issues found)
- [x] `flutter test` exit code 0 (147/147 tests passed)
- [x] Tested & launched on physical Android device physical Android device
- [x] `apps/event_gemma/README.md` updated with ADR 0006, ADR 0007, design system & verified metrics
- [x] Monorepo `README.md` and sister app READMEs synchronized
- [x] Cross-AI LLM Wiki memory (`MEMORY.md`, `architecture.md`, `conventions.md`, `log/`) synchronized



