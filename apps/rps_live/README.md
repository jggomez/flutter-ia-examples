# RPS Live

A live-camera Rock/Paper/Scissors classifier and game, running entirely on-device.

The app points the phone's camera at a hand gesture, runs it through a small
CNN via LiteRT, and turns the live classification into a "you vs. the AI"
game with a running scoreboard, plus a free-practice mode with a live
per-class confidence meter, and a persistent match history.

## Status

Built, TDD-implemented, and reviewed. `flutter analyze` is clean and
`flutter test` passes (66 tests). It has not yet been run end-to-end on a
physical device.

## How it works

- **Model**: a compact CNN (29,235 parameters) trained on the
  `drgfreeman/rockpaperscissors` Kaggle dataset — see
  `../../notebooks/Deep_Learning_tensorflow_lite_01.ipynb`. Input is a
  96x96 grayscale frame normalized to `[0, 1]`; output is a 3-class
  softmax (`paper`, `rock`, `scissors`, in that index order).
- **Inference**: `flutter_litert` loads `assets/models/rps_model.tflite`
  (the float32-I/O export, not the INT8 build the notebook also produces
  for ESP32 — see the notebook's "Export for Mobile" section).
- **Camera pipeline**: `camera` captures frames; a use case center-crops,
  resizes to 96x96, converts to grayscale, and normalizes before each
  inference call, off the UI thread.
- **State management**: Riverpod. See
  [`doc/adr/0001-state-management-riverpod.md`](doc/adr/0001-state-management-riverpod.md)
  for the choice and its addendum on the reference-counted camera/interpreter
  lifecycle needed when both the "vs. AI" and "practice" screens share it.
- **Persistence**: Hive, for match history and stats. See
  [`doc/adr/0002-persistence-hive.md`](doc/adr/0002-persistence-hive.md).

## Architecture

Layered `domain` / `data` / `ui`, with `ui/providers/repository_providers.dart`
as the single dependency-injection composition root. See
[`PLAN.md`](PLAN.md) for the full folder layout and the implementation
phase breakdown, including the post-review fix pass that resolved a
provider-lifecycle leak and a stale-cache bug caught by the review pass.

## Running

```bash
flutter pub get
flutter run
```

Requires a physical device or emulator with a working camera.

## Testing

```bash
flutter test
```

The automated suite fakes the camera and the classifier — no real camera or
model file is required to run it. `test/regression/` contains a regression
test for the provider-lifecycle bug found during review.
