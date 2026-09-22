# Model assets

Place the trained classifier here as `rps_model.tflite`.

Contract (see `lib/domain/models/classification_result.dart` and
`lib/domain/repositories/classifier_repository.dart`):

- Input tensor: `[1, 96, 96, 1]`, `float32`, single-channel grayscale,
  normalized to `[0, 1]` (`pixel / 255.0`).
- Output tensor: `[1, 3]`, `float32` softmax.
  Class order: `0 = paper`, `1 = rock`, `2 = scissors`.

This directory is declared as a Flutter asset in `pubspec.yaml`
(`assets: - assets/models/`). Do not rename the folder without updating
`ClassifierRepository` implementations and the ADRs under `doc/adr/`.

Until the real file is dropped in, `ClassifierRepositoryImpl.initialize()`
must surface a typed `ModelAssetNotFoundException` (see
`lib/domain/repositories/classifier_repository.dart`) rather than letting
the interpreter throw an opaque platform exception.
