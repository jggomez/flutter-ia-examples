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
