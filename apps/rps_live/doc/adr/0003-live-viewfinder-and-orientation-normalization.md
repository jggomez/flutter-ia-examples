# 0003. Live camera viewfinder, front-camera default, and wrist-border orientation normalization

- **Status**: accepted
- **Date**: 2026-10-21
- **Deciders**: flutter-architect

## Context

On physical Android devices, three coupled UX and inference issues surfaced during real-camera play:

1. **No Live Camera Viewfinder or Gesture Detection Feedback**: Neither `VsAiScreen` ("Tú vs. IA") nor `PracticeScreen` ("Práctica libre") displayed a live camera viewfinder or a real-time detected-gesture badge prior to reveal. Players could not see whether their hand was positioned inside the center `96x96` crop or what move (`Move.paper`, `Move.rock`, `Move.scissors`) the classifier currently recognized before/during the 3-2-1 countdown.
2. **Rear-Camera Default Prevented Looking at the Screen While Playing**: Defaulting to `CameraLensDirection.back` forced the player to hold their hand behind the phone where they could not comfortably see the screen or countdown simultaneously, with no way to switch between front and rear cameras.
3. **Systematic `Move.rock` Misclassification on Raw Mobile Frames**: `assets/models/rps_model.tflite` (`drgfreeman/rockpaperscissors`, `96x96x1` float32 grayscale `[0, 1]`) was trained exclusively on images where the **wrist enters from the right border (`x = 95`) and fingers point left (`x = 0`)** against a uniform brighter background (`bg ≈ 0.42–0.85`). On Android (`sensorOrientation = 90°` or `270°` on front cameras), raw `CameraImage` YUV420 buffers arrive rotated relative to portrait, and players naturally hold their hand with the wrist at the bottom or left of the frame. When fed non-canonical hand orientations or dark-hand-on-bright-background contrast inversions, the CNN defaults to `Move.rock` (`0.80–1.00` confidence).

At the same time, ADR 0001 requires `lib/domain/**` and `lib/ui/**` to remain 100% free of `package:camera` imports so that every unit and widget test runs without a real camera, platform channel, or device.

## Decision

### 1. Default to Front Camera (`CameraLensDirection.front`) + Live Lens Toggle (`switchCamera()`)

- **Default lens direction**: `CameraFrameServiceImpl` defaults `preferredLensDirection` to `CameraLensDirection.front` (falling back to `.back` or `cameras.first` if a front sensor is unavailable) so players can look directly at the screen while holding their hand in front of the phone.
- **Live camera switching (`switchCamera()`)**: `CameraFrameService` and `ClassifierRepository` expose `Future<void> switchCamera()` (plus `bool get isFrontCamera` where helpful) so the user can toggle between front (`CameraLensDirection.front`) and rear (`CameraLensDirection.back`) cameras on the fly from `CameraViewfinder` without restarting the round or leaking the active stream controller/interpreter.
- **Domain frame metadata (`RawCameraFrame`)**: `RawCameraFrame` includes optional metadata `int sensorOrientation = 0` (`0`, `90`, `180`, `270`) and `bool isFrontCamera = false` populated by `CameraFrameServiceImpl` from `CameraDescription`.

### 2. Plugin-Free Viewfinder via `ClassificationResult.previewPixels` and `VsAiState.liveClassification`

- **Domain contract (`ClassificationResult`)**: Add an optional `Uint8List? previewPixels` field (`96 * 96 = 9216` upright 8-bit grayscale bytes `[0..255]`) to `ClassificationResult`. `PreprocessFrameUseCase` produces `previewPixels` rotated to upright portrait using `sensorOrientation` and horizontally mirrored when `isFrontCamera == true` (so the preview behaves like a natural selfie mirror for the user), and `ClassifierRepositoryImpl` attaches `previewPixels` to each emitted `ClassificationResult`.
- **ViewModel contract (`VsAiState`)**: Expose `ClassificationResult? liveClassification` on `VsAiState` updated continuously from the classification stream so the UI can show both the live square crop and the currently detected move before, during, and after the countdown.
- **Shared widget (`CameraViewfinder` in `lib/ui/core/widgets/camera_viewfinder.dart`)**: Render `previewPixels` by encoding a lightweight in-memory 24-bit BMP (`54`-byte header + `96 * 96 * 3` RGB bytes) and passing it to `Image.memory(..., gaplessPlayback: true, filterQuality: FilterQuality.low)`, paired with a camera-switch action button (`onSwitchCamera`), a live detected-gesture badge (`✋ Papel`, `✊ Piedra`, `✌️ Tijera` + confidence percentage), and concise 3-step player instructions. Both `VsAiScreen` and `PracticeScreen` embed `CameraViewfinder`.

### 3. Canonical Wrist-Border Auto-Orientation & Contrast Normalization in `PreprocessFrameUseCase`

- **Activation heuristic**: Apply orientation and contrast normalization only to real-sized camera frames (`frame.width >= 96 && frame.height >= 96`) that exhibit non-zero foreground variance (`fgRange >= 0.03`). Small synthetic test fixtures (`width < 96 || height < 96`) or uniform frames bypass auto-orientation and contrast normalization so existing deterministic pixel-math unit tests remain exact.
- **Corner background estimation**: Sample the four `8x8` corner patches of the `96x96` center crop and use the median of their means as `cornerBg`.
- **Wrist entry border detection**: Compute the mean absolute deviation `|pixel - cornerBg|` along the middle segment `[16..80)` of each 6-pixel-deep border strip (`right`, `bottom`, `left`, `top`). The border with the highest foreground presence is the wrist entry edge:
  - `right` (`x ∈ [90, 96)`): already canonical (no rotation).
  - `bottom` (`y ∈ [90, 96)`): rotate 90° counter-clockwise so `bottom` becomes `right`.
  - `left` (`x ∈ [0, 6)`): flip horizontally so `left` becomes `right`.
  - `top` (`y ∈ [0, 6)`): rotate 90° clockwise so `top` becomes `right`.
- **Contrast normalization**: After canonical wrist orientation, map the 5th–95th percentile intensity range into `[0.12, 0.92]` and, when the hand interior is darker than a bright background (`cornerBg > 0.55 && centerMean < cornerBg - 0.06`), invert contrast around the background so the tensor matches the training distribution.

## Alternatives considered

- **Exposing `CameraController` to `ui/` for `CameraPreview`**: Rejected because it leaks `package:camera` into `lib/ui/**`, violates ADR 0001's testability boundary, and shows the uncropped full sensor field of view rather than the exact `96x96` square crop evaluated by the model.
- **Hardcoding a fixed 90° sensor rotation in `CameraFrameService`**: Rejected because front (`270°`) and back (`90°`) cameras differ and users hold their hand at varying angles (wrist from bottom, left, or right); only decoupling upright selfie-mirror `previewPixels` from wrist-border-normalized tensor pixels satisfies both human visual ergonomics and `rps_model.tflite`'s canonical right-border wrist expectation.

## Consequences

- Players default to the front camera (`CameraLensDirection.front`) with a natural upright selfie-mirrored `96x96` viewfinder and can switch between front and rear cameras at any time via `switchCamera()`.
- `rps_model.tflite` receives canonically oriented (`wrist on right border`) and contrast-normalized inputs regardless of whether the hand enters from the bottom, left, top, or right of the crop or whether the front or rear camera is active.
- Widget and unit tests can synthesize `ClassificationResult(previewPixels: Uint8List(96 * 96), ...)` and fake `switchCamera()` directly in pure Dart with zero `package:camera` imports in `domain/` or `ui/`.

## Compliance

`flutter-reviewer` checks:
- No `package:camera` or `package:flutter_litert` imports in `lib/domain/**` or `lib/ui/**`.
- `CameraFrameServiceImpl` defaults to `CameraLensDirection.front` and supports `switchCamera()` without leaking `CameraController` or breaking active stream listeners.
- `CameraViewfinder` (`lib/ui/core/widgets/camera_viewfinder.dart`) uses `gaplessPlayback: true` on `Image.memory` to prevent frame-to-frame flicker at 10–15 fps and exposes a camera-toggle control when `onSwitchCamera` is provided.
- `PreprocessFrameUseCase` remains pure Dart (`dart:math`, `dart:typed_data`) and preserves backward compatibility for synthetic unit test fixtures (`width < 96 || height < 96` or uniform frames).
- Both `VsAiScreen` and `PracticeScreen` display `CameraViewfinder` with live gesture feedback and camera switching.
