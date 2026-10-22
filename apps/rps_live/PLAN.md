# rps_live — architecture & implementation plan

"Piedra, Papel o Tijera en vivo": a live-camera Rock/Paper/Scissors classifier
game. Android + iOS only. This document is the hand-off from the
architecture phase (this file + `doc/adr/`) to the `flutter-implementer`
TDD phase.

## Architecture decisions (see `doc/adr/` for full rationale)

- **State management**: `flutter_riverpod` (v3.x), manual `Notifier` /
  `AsyncNotifier` providers, no codegen. See
  [`doc/adr/0001-state-management-riverpod.md`](doc/adr/0001-state-management-riverpod.md).
- **Persistence**: Hive (`hive` + `hive_flutter` + `hive_generator` +
  `build_runner`), one box for match history. See
  [`doc/adr/0002-persistence-hive.md`](doc/adr/0002-persistence-hive.md).
- **Camera**: `package:camera`. **Inference**: `package:flutter_litert`
  (LiteRT fork of `tflite_flutter`, interpreter-API compatible).
- **Testability boundary**: `ClassifierRepository` and `HistoryRepository`
  (both under `lib/domain/repositories/`) are the only seams the rest of the
  app depends on. Real implementations live in `lib/data/repositories/`;
  tests inject fakes via `ProviderContainer(overrides: [...])`
  (`lib/ui/providers/repository_providers.dart`). No real camera, emulator,
  or `.tflite` asset is ever required to run `flutter test`.

## Folder layout (`lib/`)

```text
lib/
├── main.dart                     # runApp(ProviderScope(...)); Hive bootstrap
├── app.dart                      # MaterialApp root
├── core/
│   └── error/app_exception.dart  # AppException base type
├── domain/                       # plain Dart, no Flutter/plugin imports
│   ├── models/
│   │   ├── move.dart                    # enum Move {paper, rock, scissors}
│   │   ├── round_outcome.dart           # enum RoundOutcome {win, lose, tie}
│   │   ├── game_phase.dart              # enum GamePhase (countdown state machine)
│   │   ├── classification_result.dart   # decoded [1,3] softmax output
│   │   ├── match_record.dart            # persisted round (domain shape)
│   │   └── raw_camera_frame.dart        # plugin-agnostic camera frame
│   ├── repositories/
│   │   ├── classifier_repository.dart   # abstract + typed exceptions
│   │   └── history_repository.dart      # abstract + typed exceptions
│   └── use_cases/
│       ├── preprocess_frame_use_case.dart       # crop/resize/grayscale/normalize
│       └── determine_round_result_use_case.dart # win/lose/tie rule
├── data/
│   ├── models/match_record_dto.dart     # Hive DTO, maps to/from MatchRecord
│   ├── services/
│   │   ├── camera_frame_service.dart       # wraps package:camera
│   │   └── tflite_classifier_service.dart  # wraps package:flutter_litert
│   ├── repositories/
│   │   ├── classifier_repository_impl.dart # composes the two services above
│   │   └── history_repository_impl.dart    # composes a Hive Box<MatchRecordDto>
│   └── local/hive_boxes.dart             # box names + typeId registry
└── ui/
    ├── core/{widgets,theme}/             # shared, feature-agnostic
    ├── providers/repository_providers.dart  # composition root (DI seam)
    └── features/
        ├── vs_ai/{view_models,views}/       # "Tú vs. IA"
        ├── practice/{view_models,views}/    # "Práctica libre"
        └── history/{view_models,views}/     # "Historial"
```

Model asset goes in `assets/models/rps_model.tflite` (declared in
`pubspec.yaml` under `flutter: assets:`; see `assets/models/README.md` for
the exact tensor contract).

## Implementation phase breakdown (for flutter-implementer, TDD)

1. **Preprocessing math** (`domain/use_cases/preprocess_frame_use_case.dart`)
   — pure Dart, test first with synthetic `RawCameraFrame` fixtures:
   center-crop to square, resize to 96x96, grayscale, normalize to
   `float32 [0,1]`. No Flutter/camera/tflite imports; fastest, highest-value
   tests to write first since everything downstream depends on correct math.
2. **Game logic** (`domain/use_cases/determine_round_result_use_case.dart`,
   `domain/models/classification_result.dart`'s `topMove`) — pure Dart,
   exhaustively test all 9 move combinations and the confidence tie-break
   rule.
3. **Persistence** (`data/models/match_record_dto.dart`,
   `data/repositories/history_repository_impl.dart`,
   `data/local/hive_boxes.dart`) — add `@HiveType`/`@HiveField` annotations,
   run `dart run build_runner build --delete-conflicting-outputs`, test
   against an in-memory Hive box (`Hive.init(tempDir)`, no platform channel).
4. **Camera + classifier integration** (`data/services/camera_frame_service.dart`,
   `data/services/tflite_classifier_service.dart`,
   `data/repositories/classifier_repository_impl.dart`) — wire real
   `package:camera` and `package:flutter_litert`; run preprocessing +
   inference off the UI isolate (`Isolate`/`compute`), targeting ~10-15 fps;
   surface `ModelAssetNotFoundException`/`CameraUnavailableException`
   instead of crashing. This phase is the hardest to unit-test directly —
   keep it a thin adapter over already-tested preprocessing/game-logic code,
   and cover it primarily via manual on-device verification plus a fake at
   the `ClassifierRepository` boundary for everything upstream.
5. **View models** (`ui/features/*/view_models/`) — `VsAiViewModel`
   (countdown/reveal/result state machine + scoreboard),
   `PracticeViewModel` (`AsyncNotifier` over the classification stream),
   `HistoryViewModel` (`AsyncNotifier` over `HistoryRepository.getAll()`).
   Test with `ProviderContainer(overrides: [classifierRepositoryProvider.overrideWithValue(fake), historyRepositoryProvider.overrideWithValue(fake)])`
   — no widgets, no camera.
6. **UI screens** (`ui/features/*/views/`) — countdown/reveal animation and
   scoreboard for `VsAiScreen`; animated per-class meters for
   `PracticeScreen`; list + aggregate stats for `HistoryScreen`. Widget-test
   each against a `ProviderScope(overrides: [...])` with fakes.
7. **Wiring** (`main.dart`) — initialize Hive
   (`Hive.initFlutter()` / register `MatchRecordDto`'s adapter / open
   `HiveBoxes.matchHistory`), construct the real
   `CameraFrameServiceImpl`/`TfliteClassifierServiceImpl`/
   `ClassifierRepositoryImpl`/`HistoryRepositoryImpl`, and override
   `classifierRepositoryProvider`/`historyRepositoryProvider` in the root
   `ProviderScope`.

## Non-goals for this plan

- Obtaining or training `rps_model.tflite` — it will be dropped into
  `assets/models/` separately.
- Routing/navigation polish between the three screens — any simple
  mechanism (bottom nav, tabs) is fine as long as each screen stays under
  its `ui/features/<feature>/views/` folder.
- Web/desktop support — explicitly out of scope (Android + iOS only).

## Post-review fix pass (flutter-implementer, 2026-09-20)

`flutter-reviewer`'s first pass on the TDD implementation (phases 1-7 above)
found two blocking bugs plus a release-config gap, fixed in this pass:

- **Camera-owning provider lifecycle leak**: `vsAiViewModelProvider` /
  `practiceViewModelProvider` / `historyViewModelProvider` are now
  `NotifierProvider.autoDispose` / `AsyncNotifierProvider.autoDispose`
  (Riverpod 3.x expresses `.autoDispose` as a provider-declaration flag, not
  a separate base class — `Notifier`/`AsyncNotifier` subclasses are
  unchanged). `ClassifierRepositoryImpl.initialize()`/`dispose()`
  (`lib/data/repositories/classifier_repository_impl.dart`) are now
  reference-counted and idempotent, and `PracticeViewModel.build()`'s
  `ref.onDispose` now also calls `classifierRepository.dispose()` (it
  previously only cancelled its own stream subscription — a second,
  related gap the new regression test caught). See the addendum to
  [`doc/adr/0001-state-management-riverpod.md`](doc/adr/0001-state-management-riverpod.md)
  for the full rationale, including why reference counting (not a plain
  "tear down and recreate") was needed once autoDispose made tab switches
  actually race an incoming screen's `initialize()` against an outgoing
  screen's `dispose()`.
- **Stale Historial data**: covered by the same `.autoDispose` fix on
  `historyViewModelProvider` — every (re)visit now re-reads Hive via a
  fresh `build()`.
- **Missing camera permission declarations**: added to
  `android/app/src/main/AndroidManifest.xml` (`CAMERA` permission +
  `uses-feature`) and `ios/Runner/Info.plist` (`NSCameraUsageDescription`).

New tests: `test/data/repositories/classifier_repository_impl_test.dart`
(direct lifecycle/reference-counting coverage against service-level fakes)
and `test/regression/classifier_lifecycle_regression_test.dart` (the
cross-feature vs_ai/practice shared-repository regression that would have
caught the original leak).

---

## On-Device UX, Live Camera Viewfinder & Wrist-Orientation Pass (2026-10-21)

### Discovery & Architecture Triage

| Criterion | Evaluation | Impact | `flutter-architect` Required? |
| :--- | :--- | :--- | :--- |
| **`>= 2` screens / widgets / notifiers modified** | Modifies `VsAiScreen`, `PracticeScreen`, `VsAiViewModel`, `PreprocessFrameUseCase`, `ClassifierRepositoryImpl`, and introduces shared `CameraViewfinder` widget (`lib/ui/core/widgets/camera_viewfinder.dart`). | Cross-feature UI + domain preprocessing pipeline | **YES (MANDATORY)** |
| **State management / domain contracts changed** | Adds `liveClassification` (`ClassificationResult?`) to `VsAiState` and optional `previewPixels` (`Uint8List?`, `96x96` grayscale crop bytes) to `ClassificationResult` so the UI renders the exact square crop the AI evaluates without leaking `package:camera` into `domain/` or `ui/`. | Updates `ClassificationResult` and `VsAiState` contracts | **YES (MANDATORY)** |
| **Navigation routes (`GoRouter`) changed** | Unchanged (bottom `NavigationBar` in `app.dart`). | None | No |
| **Native plugins / `pubspec.yaml` changed** | Unchanged (`camera` + `flutter_litert` already wired). | None | No |

### Problem Statement & Empirical Root Causes

1. **Wrong Default Camera (`CameraLensDirection.back`) & No Live Camera Viewfinder ("no veo la cámara / mi mano, no entendí el juego, ¿no se puede con la cámara de adelante?")**:
   - `CameraFrameServiceImpl` defaulted to `CameraLensDirection.back`, so while the player looked at the screen and held their hand in front of the phone, the rear camera pointed at the desk/wall (which `rps_model.tflite` always classifies as `Move.rock`).
   - Switching the default to **`CameraLensDirection.front` (selfie camera)** plus adding a **Front/Back camera toggle (`switchCamera()`)** lets the player look at the screen while showing their hand to the front camera.
   - `VsAiScreen` and `PracticeScreen` also lacked a live viewfinder, and `VsAiViewModel` kept `_latestClassification` private instead of exposing `liveClassification` on `VsAiState`.
2. **Always Classifying `rock` ("siempre me sale piedra")**:
   - `assets/models/rps_model.tflite` was trained on `drgfreeman/rockpaperscissors` (`96x96x1` grayscale), where **every training image has the wrist entering from the right border (`x = 95`) and fingers pointing left (`x = 0`)** on a uniform brighter background (`bg ≈ 0.42–0.85`).
   - On Android (`sensorOrientation = 270°` front / `90°` back), raw `CameraImage` YUV420 buffers are rotated relative to portrait, and users naturally hold their hand vertically. In non-canonical orientations or uniform/off-target frames, the CNN defaults to `Move.rock` (`0.80–1.00` confidence).
   - **Auto-Orientation & Contrast Normalization**: For real camera frames (`width >= 96 && height >= 96` with non-zero foreground variance against the four `8x8` corners), `PreprocessFrameUseCase` detects which border (`right`, `bottom`, `left`, `top`) the wrist crosses (highest mean `|pixel - cornerBg|` along the middle `[16..80]` segment), rotates/flips the `96x96` crop so the wrist is placed on the canonical `right` edge (`bottom` -> 90° CCW, `left` -> horizontal flip, `top` -> 90° CW), and normalizes contrast when the hand is darker than a bright background. Small synthetic test fixtures (`width < 96 || height < 96` or uniform frames) preserve exact raw pixel pass-through so all existing unit tests remain deterministic.

### Parallel Execution Tracks (Mode A — Disjoint File Partitioning)

| Track | Subagent | Owned Files (Strict Disjoint Scope) | Responsibilities |
| :--- | :--- | :--- | :--- |
| **Track 1 — Domain & Data Pipeline (Front Camera + Auto-Orientation + Preview)** | `flutter-implementer` | `lib/domain/models/raw_camera_frame.dart`, `lib/domain/models/classification_result.dart`, `lib/domain/repositories/classifier_repository.dart`, `lib/domain/use_cases/preprocess_frame_use_case.dart`, `lib/data/services/camera_frame_service.dart`, `lib/data/repositories/classifier_repository_impl.dart`, `test/domain/use_cases/preprocess_frame_use_case_test.dart`, `test/data/services/camera_frame_service_test.dart`, `test/data/repositories/classifier_repository_impl_test.dart`, `test/regression/classifier_lifecycle_regression_test.dart` | Default `CameraFrameServiceImpl` to `CameraLensDirection.front` and add `switchCamera()` to `CameraFrameService` & `ClassifierRepository`; add optional `sensorOrientation` / `isFrontCamera` to `RawCameraFrame`; add `previewPixels` (`96x96` upright grayscale preview) + wrist-border auto-orientation and contrast normalization in `PreprocessFrameUseCase`; wire `previewPixels` into `ClassificationResult`. |
| **Track 2 — UI Viewfinder, Camera Switch & Game UX** | `flutter-implementer` | `lib/ui/core/widgets/camera_viewfinder.dart`, `lib/ui/features/vs_ai/view_models/vs_ai_view_model.dart`, `lib/ui/features/vs_ai/views/vs_ai_screen.dart`, `lib/ui/features/practice/view_models/practice_view_model.dart`, `lib/ui/features/practice/views/practice_screen.dart`, `test/ui/features/vs_ai/view_models/vs_ai_view_model_test.dart`, `test/ui/features/vs_ai/views/vs_ai_screen_test.dart`, `test/ui/features/practice/view_models/practice_view_model_test.dart`, `test/ui/features/practice/views/practice_screen_test.dart` | Expose `liveClassification` and `switchCamera()` on `VsAiViewModel` and `PracticeViewModel`; build shared `CameraViewfinder` widget (renders 96x96 grayscale BMP `Image.memory` with `gaplessPlayback: true`, front/back camera switch button, live detected move badge `✋ Papel / ✊ Piedra / ✌️ Tijera`, and clear 3-step game instructions); integrate into `VsAiScreen` and `PracticeScreen`. |

### Verification Status (Completed 2026-10-21)
- **Architecture ADR**: [`doc/adr/0003-live-viewfinder-and-orientation-normalization.md`](doc/adr/0003-live-viewfinder-and-orientation-normalization.md) (`ACCEPTED`).
- **Static Analysis & Tests**: `flutter analyze` (`0 issues`), `flutter test` (`77/77 passing`).
- **Review & Release Verdicts**: `flutter-reviewer` (`APPROVED`), `flutter-release-engineer` (`APPROVED`).


