import 'dart:async';

import 'package:event_llm_wiki/data/repositories/chat_engine_repository_impl.dart';
import 'package:event_llm_wiki/data/services/litert_lm_service.dart';
import 'package:event_llm_wiki/domain/repositories/chat_engine_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [LitertLmService] fake — no `flutter_litert_lm` engine, no
/// real model, no native inference. Mirrors the delta-stream contract
/// documented on `LitertLmService.sendMessageStream`.
class _FakeLitertLmService implements LitertLmService {
  int initializeCallCount = 0;
  int disposeCallCount = 0;
  String? lastModelPath;

  /// If set, [initialize] throws this instead of succeeding.
  Object? initializeError;

  StreamController<String>? _activeController;
  String? lastPrompt;

  @override
  Future<void> initialize({required String modelPath}) async {
    initializeCallCount++;
    lastModelPath = modelPath;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Stream<String> sendMessageStream(String prompt) {
    lastPrompt = prompt;
    final controller = StreamController<String>();
    _activeController = controller;
    return controller.stream;
  }

  void emit(String delta) => _activeController?.add(delta);

  void emitError(Object error) => _activeController?.addError(error);

  Future<void> completeStream() async => _activeController?.close();

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

void main() {
  group('ChatEngineRepositoryImpl', () {
    test('initialize() loads the model at the configured path', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );

      await repository.initialize();

      expect(service.initializeCallCount, 1);
      expect(service.lastModelPath, '/tmp/model.litertlm');
    });

    test('initialize() is idempotent: a second call is a no-op', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );

      await repository.initialize();
      await repository.initialize();
      await repository.initialize();

      expect(service.initializeCallCount, 1);
    });

    test(
      'initialize() wraps a service failure in ModelLoadException',
      () async {
        final service = _FakeLitertLmService()
          ..initializeError = Exception('corrupt file');
        final repository = ChatEngineRepositoryImpl(
          litertLmService: service,
          modelPath: '/tmp/model.litertlm',
        );

        expect(
          () => repository.initialize(),
          throwsA(isA<ModelLoadException>()),
        );
      },
    );

    test('a failed initialize() leaves the repository able to retry '
        '(not stuck "initialized")', () async {
      final service = _FakeLitertLmService()
        ..initializeError = Exception('corrupt file');
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );

      await repository.initialize().catchError((_) {});
      service.initializeError = null;
      await repository.initialize();

      expect(service.initializeCallCount, 2);
    });

    test('sendMessage passes the prompt through and forwards deltas '
        'unmodified', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );
      await repository.initialize();

      final received = <String>[];
      final done = Completer<void>();
      repository
          .sendMessage('What is talk-001 about?')
          .listen(received.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      service.emit('Hello');
      service.emit(', world');
      await service.completeStream();
      await done.future;

      expect(service.lastPrompt, 'What is talk-001 about?');
      expect(received, ['Hello', ', world']);
    });

    test('sendMessage surfaces a stream error as InferenceException', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );
      await repository.initialize();

      final errors = <Object>[];
      final done = Completer<void>();
      repository
          .sendMessage('hi')
          .listen(
            (_) {},
            onError: (Object error) {
              errors.add(error);
              done.complete();
            },
            cancelOnError: true,
          );
      await Future<void>.delayed(Duration.zero);
      service.emitError(Exception('mid-stream failure'));
      await done.future;

      expect(errors, hasLength(1));
      expect(errors.single, isA<InferenceException>());
    });

    test('dispose() releases the service and is idempotent', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );
      await repository.initialize();

      await repository.dispose();
      await repository.dispose();

      expect(service.disposeCallCount, 1);
    });

    test('dispose() before initialize() is a safe no-op', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );

      await repository.dispose();

      expect(service.disposeCallCount, 0);
    });

    test('initialize() after dispose() re-initializes (not stuck '
        'disposed)', () async {
      final service = _FakeLitertLmService();
      final repository = ChatEngineRepositoryImpl(
        litertLmService: service,
        modelPath: '/tmp/model.litertlm',
      );
      await repository.initialize();
      await repository.dispose();

      await repository.initialize();

      expect(service.initializeCallCount, 2);
    });
  });
}
