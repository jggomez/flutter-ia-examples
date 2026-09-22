import 'dart:typed_data';

// This app is Android/iOS only (see PLAN.md), so the native-only barrel is
// imported unconditionally rather than `package:flutter_litert/flutter_litert.dart`
// (whose portable/WASM-safe surface resolves `InterpreterFactory` away
// during static analysis — see that package's `native.dart` doc comment).
import 'package:flutter_litert/native.dart';

import '../../domain/repositories/classifier_repository.dart';

/// Thin wrapper around the `flutter_litert` interpreter.
///
/// Kept separate from [CameraFrameService] and from
/// `ClassifierRepositoryImpl` so the interpreter can be faked
/// (`FakeTfliteClassifierService` returning canned `Float32List` outputs) in
/// tests that never touch `assets/models/rps_model.tflite`.
abstract class TfliteClassifierService {
  /// Loads `assets/models/rps_model.tflite` and validates its input/output
  /// tensor shapes against the documented model contract
  /// (input `[1, 96, 96, 1]` float32, output `[1, 3]` float32 softmax).
  ///
  /// Throws `ModelAssetNotFoundException`
  /// (`domain/repositories/classifier_repository.dart`) if the asset is
  /// missing or fails validation — this is the required typed failure mode
  /// for "model not dropped in yet", not a crash.
  Future<void> load();

  /// Runs one inference. [normalizedGrayscaleInput] must already be the
  /// preprocessed, flattened `96*96` float32 buffer in `[0, 1]` produced by
  /// `PreprocessFrameUseCase`. Returns the raw `[paper, rock, scissors]`
  /// softmax output.
  Float32List classify(Float32List normalizedGrayscaleInput);

  Future<void> dispose();
}

/// Real implementation backed by `package:flutter_litert`.
///
/// This class's methods are invoked from
/// `ClassifierRepositoryImpl`'s background isolate/`compute` entry point,
/// not directly from the UI isolate.
class TfliteClassifierServiceImpl implements TfliteClassifierService {
  TfliteClassifierServiceImpl({
    this.modelAssetPath = 'assets/models/rps_model.tflite',
  });

  final String modelAssetPath;

  static const int _inputSize = 96;
  static const int _outputClassCount = 3;
  static const _expectedInputShape = [1, _inputSize, _inputSize, 1];
  static const _expectedOutputShape = [1, _outputClassCount];

  Interpreter? _interpreter;

  @override
  Future<void> load() async {
    // Defensive idempotency: close any interpreter left over from a
    // previous `load()` that was never followed by a matching `dispose()`
    // before creating a new one, so this never leaks a native `Interpreter`
    // regardless of caller discipline (the intended caller,
    // `ClassifierRepositoryImpl`, reference-counts so this should already
    // be null in practice — see that class's `_activeSessions` doc
    // comment — but this stays safe even if called directly).
    _interpreter?.close();
    _interpreter = null;

    final Interpreter interpreter;
    try {
      // `PerformanceConfig.auto` picks XNNPACK (Android) / GPU (iOS) when
      // available, falling back to plain CPU — this is the package's
      // supported way to accelerate the small per-frame `run()` call below
      // without the added complexity of a cross-isolate `IsolateInterpreter`
      // (see the class doc comment on `ClassifierRepositoryImpl` for why
      // inference itself is kept synchronous on the calling isolate).
      final (options, _) = InterpreterFactory.create(const PerformanceConfig());
      interpreter = await Interpreter.fromAsset(
        modelAssetPath,
        options: options,
      );
    } catch (error) {
      throw ModelAssetNotFoundException(
        'Could not load "$modelAssetPath" — make sure rps_model.tflite has '
        'been dropped into assets/models/ (see assets/models/README.md).',
        cause: error,
      );
    }

    final inputShape = interpreter.getInputTensor(0).shape;
    final outputShape = interpreter.getOutputTensor(0).shape;
    if (!_shapesMatch(inputShape, _expectedInputShape) ||
        !_shapesMatch(outputShape, _expectedOutputShape)) {
      interpreter.close();
      throw ModelAssetNotFoundException(
        '"$modelAssetPath" has an unexpected tensor shape (input: '
        '$inputShape, output: $outputShape); expected input '
        '$_expectedInputShape and output $_expectedOutputShape per the '
        'documented model contract (assets/models/README.md).',
      );
    }

    _interpreter = interpreter;
  }

  @override
  Float32List classify(Float32List normalizedGrayscaleInput) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError(
        'TfliteClassifierServiceImpl.load() must complete successfully '
        'before classify() is called.',
      );
    }
    if (normalizedGrayscaleInput.length != _inputSize * _inputSize) {
      throw ArgumentError.value(
        normalizedGrayscaleInput.length,
        'normalizedGrayscaleInput.length',
        'Expected exactly ${_inputSize * _inputSize} values (a flattened '
            '$_inputSize x $_inputSize grayscale frame from '
            'PreprocessFrameUseCase).',
      );
    }

    // Reshape the flat [96*96] buffer into the [1, 96, 96, 1] nested list
    // shape the interpreter's `run` expects.
    final input = [
      List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final value = normalizedGrayscaleInput[y * _inputSize + x];
          return [value];
        }),
      ),
    ];
    final output = [List<double>.filled(_outputClassCount, 0.0)];

    interpreter.run(input, output);

    return Float32List.fromList(output.first);
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }

  bool _shapesMatch(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        return false;
      }
    }
    return true;
  }
}
