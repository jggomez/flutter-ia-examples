import 'dart:async';
import 'dart:typed_data';

import 'package:rps_live/data/services/camera_frame_service.dart';
import 'package:rps_live/data/services/tflite_classifier_service.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/raw_camera_frame.dart';
import 'package:rps_live/domain/repositories/classifier_repository.dart';
import 'package:rps_live/domain/repositories/history_repository.dart';

/// In-memory [ClassifierRepository] fake: no camera hardware, no emulator
/// and no real `.tflite` asset are ever touched. Tests drive
/// [emit]/[emitError] to simulate the live classifier stream, and
/// [initializeError] to simulate `ModelAssetNotFoundException` /
/// `CameraUnavailableException` on [initialize].
class FakeClassifierRepository implements ClassifierRepository {
  final _controller = StreamController<ClassificationResult>.broadcast();

  /// If set, [initialize] throws this instead of succeeding.
  Object? initializeError;

  int initializeCallCount = 0;
  int disposeCallCount = 0;
  bool get isInitialized => initializeCallCount > 0 && initializeError == null;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Stream<ClassificationResult> get classificationStream => _controller.stream;

  void emit(ClassificationResult result) => _controller.add(result);

  void emitError(Object error, [StackTrace? stackTrace]) =>
      _controller.addError(error, stackTrace ?? StackTrace.current);

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

/// In-memory [HistoryRepository] fake backed by a plain `List<MatchRecord>`
/// — no Hive box, no filesystem, no platform channel.
class FakeHistoryRepository implements HistoryRepository {
  FakeHistoryRepository({List<MatchRecord>? seed}) : _records = [...?seed];

  final List<MatchRecord> _records;

  /// If set, [add] throws this instead of succeeding.
  Object? addError;

  /// If set, [getAll] throws this instead of succeeding.
  Object? getAllError;

  @override
  Future<List<MatchRecord>> getAll() async {
    final error = getAllError;
    if (error != null) {
      throw error;
    }
    return List.unmodifiable(_records);
  }

  @override
  Future<void> add(MatchRecord record) async {
    final error = addError;
    if (error != null) {
      throw error;
    }
    _records.add(record);
  }

  @override
  Future<void> clear() async {
    _records.clear();
  }
}

/// In-memory [CameraFrameService] fake used to test `ClassifierRepositoryImpl`
/// directly (as opposed to [FakeClassifierRepository], which fakes the whole
/// repository and therefore can't exercise
/// `ClassifierRepositoryImpl`'s own initialize/dispose lifecycle logic).
///
/// [listenerCount] tracks how many active listeners [frames] currently has,
/// letting tests assert the repository never leaves more than one internal
/// frame subscription live at a time.
class FakeCameraFrameService implements CameraFrameService {
  FakeCameraFrameService()
    : _controller = StreamController<RawCameraFrame>.broadcast() {
    _controller.onListen = () => listenerCount++;
    _controller.onCancel = () => listenerCount--;
  }

  final StreamController<RawCameraFrame> _controller;

  int startCallCount = 0;
  int stopCallCount = 0;
  int listenerCount = 0;

  /// If set, [start] throws this instead of succeeding.
  Object? startError;

  @override
  Future<void> start() async {
    startCallCount++;
    final error = startError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Stream<RawCameraFrame> get frames => _controller.stream;

  void emitFrame(RawCameraFrame frame) => _controller.add(frame);

  @override
  Future<void> stop() async {
    stopCallCount++;
  }
}

/// In-memory [TfliteClassifierService] fake used to test
/// `ClassifierRepositoryImpl` directly, with no real `.tflite` asset or
/// native `Interpreter` involved.
class FakeTfliteClassifierService implements TfliteClassifierService {
  int loadCallCount = 0;
  int disposeCallCount = 0;
  bool _loaded = false;

  /// If set, [load] throws this instead of succeeding.
  Object? loadError;

  /// Canned output for [classify]; defaults to a fixed "paper" softmax.
  Float32List Function(Float32List input) classifyResult = (_) =>
      Float32List.fromList([1, 0, 0]);

  @override
  Future<void> load() async {
    loadCallCount++;
    final error = loadError;
    if (error != null) {
      throw error;
    }
    _loaded = true;
  }

  @override
  Float32List classify(Float32List normalizedGrayscaleInput) {
    if (!_loaded) {
      throw StateError('load() must complete before classify().');
    }
    return classifyResult(normalizedGrayscaleInput);
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    _loaded = false;
  }
}
