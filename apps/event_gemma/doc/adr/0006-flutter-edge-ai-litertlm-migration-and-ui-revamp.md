# 0006. Runtime Engine Migration to flutter_edge_ai_litertlm & Complete UI/UX Redesign Pass

- **Status**: accepted
- **Date**: 2026-10-22
- **Deciders**: flutter-architect

## Context

`event_llm_wiki` delivers a fully offline, on-device AI assistant for conference attendees, pairing a bundled agenda wiki with lexical RAG retrieval and a local Gemma 3 1B-IT language model.

Two primary architectural and user experience drivers necessitate this ADR:

1. **Inference Runtime Ecosystem Maturity (`flutter_edge_ai_litertlm` vs `flutter_litert_lm`)**:
   - In ADR 0001, `flutter_litert_lm: ^0.3.0` was selected as the minimal wrapper around Google's LiteRT-LM runtime. However, real-world community adoption and ongoing maintenance heavily favor **`flutter_edge_ai`** (`^2.5.1`) paired with **`flutter_edge_ai_litertlm`** (`^1.17.0`) — boasting 640+ GitHub stars, 5.4k+ monthly downloads, active multi-engine abstraction, and robust production-tested LiteRT-LM engine bindings.
   - `flutter_edge_ai_litertlm` provides first-class support for `.litertlm` model files, explicit hardware fallback (`backendFallback: true`), declarative model installation lifecycles (`FlutterEdgeAi.installModel(...).fromFile(...).install()`), and clean conversational sessions (`createChat()` and `generateChatResponseAsync()`).

2. **UI/UX Maturation from Functional Prototype to Modern AI Conference Experience**:
   - The initial release focused on architectural verification (phases 1–12 in `PLAN.md`): basic unstyled `ListTile`s in `AgendaListScreen`, plain text view in `TalkDetailScreen`, bare message containers in `ChatScreen` without suggestion prompts or generation indicators, and a plain text-heavy setup view in `ModelSetupScreen`.
   - A modern on-device AI conference application requires a cohesive, premium design system:
     - Centralized design system tokens (colors, typography, elevation, shape) in `lib/ui/core/theme/`.
     - An engaging, scannable agenda with interactive Day/Track filter chips and rich talk cards.
     - A structured talk detail view with speaker profiles and contextual "Ask AI about this talk" shortcuts.
     - A conversational AI interface featuring prompt suggestion pills, pulsing generation indicators, asymmetric bubble styling, and interactive citation chips.
     - A confidence-inspiring model setup onboarding card emphasizing privacy (100% offline, zero cloud telemetry, on-device storage).

---

## Decision

### 1. Inference Engine Migration: `flutter_edge_ai` & `flutter_edge_ai_litertlm`

Replace `flutter_litert_lm: ^0.3.0` in `pubspec.yaml` with:
```yaml
dependencies:
  flutter_edge_ai: ^2.5.1
  flutter_edge_ai_litertlm: ^1.17.0
```

#### Encapsulation in `LitertLmService`
In strict alignment with ADR 0001 and ADR 0003, **`lib/data/services/litert_lm_service.dart` remains the ONLY file in the entire repository permitted to import `package:flutter_edge_ai` or `package:flutter_edge_ai_litertlm`**.

`LitertLmServiceImpl` encapsulates the new runtime API:
```dart
@override
Future<void> initialize({required String modelPath}) async {
  await FlutterEdgeAi.initialize(
    inferenceEngines: [const LiteRtLmEngine(backendFallback: true)],
  );
  final model = await FlutterEdgeAi.installModel(
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.litertlm,
  ).fromFile(modelPath).install();

  _model = model;
  _chat = await model.createChat();
}

@override
Stream<String> sendMessageStream(String prompt) {
  final chat = _chat;
  if (chat == null) {
    throw StateError(
      'LitertLmServiceImpl.initialize() must complete successfully before sendMessageStream().',
    );
  }
  // Maps asynchronous chunk responses to a stream of delta strings
  return chat.generateChatResponseAsync(prompt);
}

@override
Future<void> dispose() async {
  await _chat?.dispose();
  _chat = null;
  await _model?.dispose();
  _model = null;
}
```

#### Unchanged Delta-Streaming Contract
`LitertLmService.sendMessageStream(String prompt)` preserves its exact signature and semantics: returning a `Stream<String>` where each emitted event is a newly generated text delta (chunk). 

Consequently:
- **Zero changes** to `ChatEngineRepository` (`lib/domain/repositories/chat_engine_repository.dart`).
- **Zero changes** to `ChatEngineRepositoryImpl` (`lib/data/repositories/chat_engine_repository_impl.dart`).
- **Zero changes** to `ChatViewModel` (`lib/ui/features/chat/view_models/chat_view_model.dart`).
- **Zero changes** to unit test fakes (`_FakeLitertLmService` in test suites, `FakeChatEngineRepository` in `test/support/fakes.dart`).

---

### 2. UI/UX Design System & Component Architecture

Centralize design tokens in `lib/ui/core/theme/` (`app_theme.dart`, `app_colors.dart`, `app_typography.dart`):

#### A. Color Palette & Visual Tokens
- **Seed / Primary**: Deep Indigo / Violet (`#4F46E5` / `#6366F1`) reflecting AI intelligence and precision.
- **Accent / Secondary**: Luminous Cyan / Teal (`#06B6D4` / `#14B8A6`) for interactive states, active filter chips, and streaming pulse cues.
- **Surface Container Hierarchy**: High-contrast Material 3 surfaces (`surfaceContainerLowest`, `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest`) providing depth and content hierarchy without heavy skeuomorphic drop shadows.
- **Shape & Elevation**:
  - Cards: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))`
  - Filter & Citation Chips: `StadiumBorder` or `BorderRadius.circular(12)`
  - Chat Bubbles: Asymmetric rounded corners (`BorderRadius.only(topLeft: 18, topRight: 18, bottomLeft/Right: 4, ...)`).

#### B. Component Specifications

##### 1. `AgendaListScreen` (`lib/ui/features/agenda/views/agenda_list_screen.dart`)
- **Enriched Day Filter**: Horizontally scrollable chip row or segmented bar (`Day 1`, `Day 2`, etc.) with active pill highlighting (cyan/indigo container) and instant talk filtering.
- **Categorical Track Chips**: Color-coded badges for tracks (e.g. Flutter = Cyan/Indigo, AI/ML = Violet/Purple, Cloud = Teal, Systems = Amber/Orange).
- **Rich Talk Cards**:
  - Elevated surface container card (`surfaceContainerLow`).
  - Leading time badge (`Icons.schedule_rounded`) displaying start and duration.
  - Track badge and room metadata.
  - Prominent title (`titleMedium`, semibold).
  - Speaker profile pill with initials avatar and speaker name.
  - Trailing chevron cue indicating navigable detail.

##### 2. `TalkDetailScreen` (`lib/ui/features/agenda/views/talk_detail_screen.dart`)
- **Hero Header**: Prominent container with subtle gradient backdrop, bold talk title (`headlineSmall`), and high-contrast back navigation.
- **Information Ribbon**: Horizontal metadata row displaying Day, Track, Room, and Time with contextual icons.
- **Speaker Profile Card**:
  - Circular avatar / initials container with subtle accent border.
  - Speaker name (`titleMedium`, bold) and organization/role.
  - Speaker bio card.
- **Abstract Card**: Readable typography (`bodyLarge`, 1.5 line height) inside `surfaceContainerHighest` card.
- **Interactive "Ask AI about this talk" CTA**: Prominent filled tonal button with `Icons.auto_awesome` at the bottom or floating, routing to the Chat tab with pre-seeded query context (e.g., *"Tell me more about [talk title] by [speaker]"*).

##### 3. `ChatScreen` (`lib/ui/features/chat/views/chat_screen.dart`)
- **Asymmetric AI Message Bubbles**:
  - **User**: Aligned right, `primaryContainer` fill, `onPrimaryContainer` typography, rounded corners with clipped bottom-right corner (`BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4))`).
  - **Assistant**: Aligned left, `surfaceContainerHighest` fill with subtle outline, `onSurface` typography, rounded corners with clipped bottom-left corner (`BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4))`).
- **Prompt Suggestion Pills**:
  - Rendered when chat history is empty or as quick discovery starters above the input bar.
  - Quick prompts: *"What are the keynote sessions?"*, *"Summarize Day 1 Flutter talks"*, *"Which sessions cover on-device Gemma?"*, *"Show me talks on LiteRT"*.
  - Tapping a pill immediately dispatches or populates the query.
- **Pulsing Generation Indicator**:
  - Rendered while the assistant response is in-flight before the first token arrives or during active token generation.
  - Smooth three-dot pulsing/shimmering indicator in accent cyan/violet, providing immediate feedback.
- **Enhanced Citation Chips**:
  - Embedded directly below assistant answers when citations exist.
  - Interactive pill showing `Icons.bookmark_outline`, talk title, and direct tap navigation to `TalkDetailScreen`.
- **Modern Input Field**:
  - Floating rounded pill (`BorderRadius.circular(28)`) with hint *"Ask about any talk, speaker, or track…"*.
  - Circular send button with gradient/accent tint, disabled when input is whitespace-only.

##### 4. `ModelSetupScreen` (`lib/ui/features/setup/views/model_setup_screen.dart`)
- **Hero Onboarding Card**:
  - Premium AI iconography (`Icons.auto_awesome_motion_rounded`) with glowing/gradient accent container.
  - Clear value proposition: *"On-Device AI Assistant — 100% Offline & Private"*.
  - Key privacy bullet points: Zero cloud telemetry, no data sent over the network, model runs directly on device silicon.
- **Model Specification & Storage Meter**:
  - Model name: `Gemma 3 1B-IT (int4 quantized)`.
  - Download size: `~529 MB` with storage footprint visual meter.
  - Active Wi-Fi badge (green check for active Wi-Fi; warning indicator if on cellular or offline).
- **Polished Download Flow**:
  - Elevated CTA button initiating the Wi-Fi confirmation dialog.
  - Live progress display during download featuring animated progress bar, percentage, and downloaded byte counter.

---

## Consequences

- **100% Model Compatibility**:
  - The model file downloaded by `ModelDownloadRepositoryImpl` (`gemma3-1b-it-int4.litertlm`, ~529 MB, 4096 context tokens) is fully compatible with `flutter_edge_ai_litertlm`'s `LiteRtLmEngine`.
  - No changes are needed for the Hugging Face download endpoint, size validation logic (`ValidateDownloadedModelUseCase`), or file storage path (`AppStorageService`).
- **Strict Layer Separation Preserved**:
  - `package:flutter_edge_ai` and `package:flutter_edge_ai_litertlm` are completely encapsulated within `lib/data/services/litert_lm_service.dart`.
  - Domain models, repositories, and UI view models remain 100% decoupled from third-party inference SDKs.
- **Deterministic Testability**:
  - Real native inference engines and model files remain strictly prohibited from `flutter test`.
  - All unit and widget tests continue to run reliably and deterministically using `_FakeLitertLmService` and `FakeChatEngineRepository`.
- **60fps / 120fps Frame Budget Compliance**:
  - Chat streaming appends text deltas to the active `ChatMessage`; list rendering must avoid full rebuilds on every character delta (using efficient `ListView.builder` keys).
  - All widget `build()` methods must remain pure: no synchronous file I/O, no regex compilation in hot loops, and no JSON decoding.
  - Animations (pulsing generation dots, shimmer indicators) must use standard ticker-driven `AnimationController`s with mandatory `.dispose()` calls to prevent leaks.

---

## Alternatives Considered

- **Retaining `flutter_litert_lm`**:
  - *Rejected*: Limited community adoption, lack of upstream maintenance, and missing declarative multi-engine abstraction.
- **Migrating to `flutter_gemma` (MediaPipe GenAI)**:
  - *Rejected*: MediaPipe GenAI requires distinct `.bin` task bundles rather than `.litertlm` format, and bundles opinionated retrieval/session logic that duplicates our custom, lightweight lexical RAG pipeline (ADR 0002).
- **Hardcoded Dark-Only Cyberpunk Theme**:
  - *Rejected*: A flexible Material 3 tech design system based on dynamic color tokens supports high contrast and accessibility across both Light and Dark system modes.

---

## Compliance

### `flutter-reviewer` Checklist:
- [ ] `package:flutter_edge_ai` and `package:flutter_edge_ai_litertlm` are imported **ONLY** in `lib/data/services/litert_lm_service.dart`.
- [ ] No files in `lib/domain/**` or `lib/ui/**` import any inference runtime packages.
- [ ] `LitertLmService.sendMessageStream` continues to return `Stream<String>` with delta-stream semantics.
- [ ] `lib/ui/core/theme/` contains all centralized design tokens (colors, typography, theme data).
- [ ] `AgendaListScreen` provides Day filter chips, Track color badges, and rich talk cards.
- [ ] `TalkDetailScreen` includes a hero header, speaker profile card, and "Ask AI about this talk" CTA.
- [ ] `ChatScreen` implements asymmetric bubbles, prompt suggestion pills, pulsing generation indicator, and citation chips.
- [ ] `ModelSetupScreen` displays the hero onboarding card with privacy guarantees and Wi-Fi confirmation dialog.
- [ ] All controllers (`TextEditingController`, `AnimationController`, `ScrollController`) call `.dispose()`.
- [ ] `BuildContext` across async gaps is guarded with `if (!context.mounted) return;`.

### `flutter-release-engineer` Checklist:
- [ ] `pubspec.yaml` specifies `flutter_edge_ai: ^2.5.1` and `flutter_edge_ai_litertlm: ^1.17.0`, and completely removes `flutter_litert_lm`.
- [ ] Android build configurations (`android/app/build.gradle`, `minSdkVersion`, NDK) remain compatible with LiteRT-LM runtime requirements.
- [ ] The bundled `assets/agenda.json` asset remains intact and declared in `pubspec.yaml`.
- [ ] `flutter test` executes with zero failures and does not invoke native plugins or network calls.
