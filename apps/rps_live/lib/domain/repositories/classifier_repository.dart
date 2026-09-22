import '../../core/error/app_exception.dart';
import '../models/classification_result.dart';

/// Abstraction over the entire camera + on-device classifier pipeline.
///
/// This is the single seam the rest of the app depends on for live
/// inference. It intentionally hides `package:camera`, `package:flutter_litert`
/// and all Dart-side preprocessing behind one interface so that:
///
/// - `flutter-implementer` can write a real implementation
///   (`data/repositories/classifier_repository_impl.dart`) composed from a
///   camera frame service and a tflite interpreter service, running
///   preprocessing + inference off the UI isolate (`Isolate`/`compute`).
/// - Unit/widget tests provide a `FakeClassifierRepository` that emits
///   canned [ClassificationResult]s on a `StreamController`, with no camera
///   hardware, no emulator and no real `.tflite` asset required.
///
/// Game logic (round win/lose/tie, scoreboard) and the live confidence meter
/// both consume [classificationStream]; neither should talk to `camera` or
/// `flutter_litert` directly.
abstract class ClassifierRepository {
  /// Loads the model asset and starts the camera. Must be called before
  /// [classificationStream] emits.
  ///
  /// Throws:
  /// - [ModelAssetNotFoundException] if `assets/models/rps_model.tflite` is
  ///   missing or fails to load as a valid interpreter (this is the
  ///   documented failure mode for the "model dropped in later" case — it
  ///   must never surface as an unhandled platform crash).
  /// - [CameraUnavailableException] if the camera cannot be opened
  ///   (permission denied, no camera hardware, camera already in use).
  Future<void> initialize();

  /// A live stream of classifier output, sampled at roughly 10-15 fps.
  /// Must only be listened to after [initialize] completes successfully.
  Stream<ClassificationResult> get classificationStream;

  /// Releases the camera and interpreter. Safe to call multiple times.
  Future<void> dispose();
}

/// Thrown by [ClassifierRepository.initialize] when
/// `assets/models/rps_model.tflite` is missing, unreadable, or fails
/// interpreter validation (wrong input/output tensor shape, etc.).
///
/// The UI layer MUST catch this and show a typed "model missing / broken"
/// state instead of letting the app crash — see the ADR at
/// `doc/adr/0001-state-management-riverpod.md` for the compliance rule.
class ModelAssetNotFoundException extends AppException {
  const ModelAssetNotFoundException(super.message, {super.cause});
}

/// Thrown by [ClassifierRepository.initialize] when the camera cannot be
/// started (permission denied, no camera hardware, already in use by
/// another app).
class CameraUnavailableException extends AppException {
  const CameraUnavailableException(super.message, {super.cause});
}
