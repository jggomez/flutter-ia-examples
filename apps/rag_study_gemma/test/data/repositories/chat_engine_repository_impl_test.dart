import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/repositories/chat_engine_repository_impl.dart';
import 'package:rag_study_gemma/data/services/app_storage_service.dart';
import 'package:rag_study_gemma/data/services/edge_ai_rag_service.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/repositories/chat_engine_repository.dart';

class _FakeAppStorageService implements AppStorageService {
  @override
  Future<String> get embeddingModelFilePath async => '/models/embed.litertlm';

  @override
  Future<String> get llmModelFilePath async => '/models/gemma3.litertlm';

  @override
  Future<String> get ragSqliteDbPath async => '/db/rag.sqlite';
}

class _FakeEdgeAiRagService implements EdgeAiRagService {
  int initLlmCount = 0;
  int resetCount = 0;
  int disposeLlmCount = 0;
  List<String> tokens = const ['Hello ', 'student!'];
  Object? error;

  @override
  Future<void> ensureRuntimeInitialized() async {}

  @override
  Future<void> initializeRagIndex({
    required String embeddingModelPath,
    required String sqliteDbPath,
  }) async {}

  @override
  Future<void> addDocumentChunk(DocumentChunk chunk) async {}

  @override
  Future<List<RetrievedChunk>> searchChunks({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async => const [];

  @override
  Future<void> removeChunks(List<String> chunkIds) async {}

  @override
  Future<void> disposeRagIndex() async {}

  @override
  Future<void> initializeLlm({required String llmModelPath}) async {
    if (error != null) throw error!;
    initLlmCount++;
  }

  @override
  Stream<String> sendMessageStream(String prompt) {
    if (error != null) {
      return Stream<String>.error(error!);
    }
    return Stream<String>.fromIterable(tokens);
  }

  @override
  Future<void> resetConversation() async {
    if (error != null) throw error!;
    resetCount++;
  }

  @override
  Future<void> disposeLlm() async {
    disposeLlmCount++;
  }
}

void main() {
  group('ChatEngineRepositoryImpl', () {
    late _FakeEdgeAiRagService fakeEdgeAi;
    late _FakeAppStorageService fakeStorage;
    late ChatEngineRepositoryImpl repository;

    setUp(() {
      fakeEdgeAi = _FakeEdgeAiRagService();
      fakeStorage = _FakeAppStorageService();
      repository = ChatEngineRepositoryImpl(
        edgeAiRagService: fakeEdgeAi,
        appStorageService: fakeStorage,
      );
    });

    test('initialize is idempotent and loads LLM once', () async {
      await repository.initialize();
      await repository.initialize();
      expect(fakeEdgeAi.initLlmCount, equals(1));
    });

    test('initialize wraps failures in ModelLoadException', () async {
      fakeEdgeAi.error = Exception('Model weights corrupt');
      await expectLater(
        () => repository.initialize(),
        throwsA(isA<ModelLoadException>()),
      );
    });

    test(
      'sendMessage streams tokens and maps errors to InferenceException',
      () async {
        await repository.initialize();
        final tokens = await repository.sendMessage('Explain SGD').toList();
        expect(tokens, equals(['Hello ', 'student!']));

        fakeEdgeAi.error = StateError('Engine crashed');
        await expectLater(
          repository.sendMessage('Explain SGD').toList(),
          throwsA(isA<InferenceException>()),
        );
      },
    );

    test(
      'resetConversation and dispose delegate to EdgeAiRagService',
      () async {
        await repository.initialize();
        await repository.resetConversation();
        expect(fakeEdgeAi.resetCount, equals(1));

        await repository.dispose();
        expect(fakeEdgeAi.disposeLlmCount, equals(1));
      },
    );
  });
}
