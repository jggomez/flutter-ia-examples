import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/repositories/rag_index_repository_impl.dart';
import 'package:rag_study_gemma/data/services/app_storage_service.dart';
import 'package:rag_study_gemma/data/services/edge_ai_rag_service.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/repositories/rag_index_repository.dart';

class _FakeAppStorageService implements AppStorageService {
  @override
  Future<String> get embeddingModelFilePath async => '/models/embed.litertlm';

  @override
  Future<String> get llmModelFilePath async => '/models/llm.litertlm';

  @override
  Future<String> get ragSqliteDbPath async => '/db/rag.sqlite';
}

class _FakeEdgeAiRagService implements EdgeAiRagService {
  int initRagCount = 0;
  int disposeRagCount = 0;
  final List<DocumentChunk> addedChunks = [];
  final List<String> removedChunkIds = [];
  List<RetrievedChunk> searchResults = [];
  Object? error;

  @override
  Future<void> ensureRuntimeInitialized() async {}

  @override
  Future<void> initializeRagIndex({
    required String embeddingModelPath,
    required String sqliteDbPath,
  }) async {
    if (error != null) throw error!;
    initRagCount++;
  }

  @override
  Future<void> addDocumentChunk(DocumentChunk chunk) async {
    if (error != null) throw error!;
    addedChunks.add(chunk);
  }

  @override
  Future<List<RetrievedChunk>> searchChunks({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async {
    if (error != null) throw error!;
    return searchResults;
  }

  @override
  Future<void> removeChunks(List<String> chunkIds) async {
    if (error != null) throw error!;
    removedChunkIds.addAll(chunkIds);
  }

  @override
  Future<void> disposeRagIndex() async {
    disposeRagCount++;
  }

  @override
  Future<void> initializeLlm({required String llmModelPath}) async {}

  @override
  Stream<String> sendMessageStream(String prompt) => const Stream.empty();

  @override
  Future<void> resetConversation() async {}

  @override
  Future<void> disposeLlm() async {}
}

void main() {
  group('RagIndexRepositoryImpl', () {
    late _FakeEdgeAiRagService fakeEdgeAi;
    late _FakeAppStorageService fakeStorage;
    late RagIndexRepositoryImpl repository;

    setUp(() {
      fakeEdgeAi = _FakeEdgeAiRagService();
      fakeStorage = _FakeAppStorageService();
      repository = RagIndexRepositoryImpl(
        edgeAiRagService: fakeEdgeAi,
        appStorageService: fakeStorage,
      );
    });

    test(
      'initialize is idempotent and delegates to EdgeAiRagService',
      () async {
        await repository.initialize();
        await repository.initialize();
        expect(fakeEdgeAi.initRagCount, equals(1));
      },
    );

    test('addChunks auto-initializes, adds chunks with progress, and search retrieves them', () async {
      const chunk1 = DocumentChunk(
        id: 'd1_p1_c0',
        docId: 'd1',
        docTitle: 'Calculus',
        pageNumber: 1,
        chunkIndex: 0,
        content: 'Derivative is the instantaneous rate of change.',
      );
      const chunk2 = DocumentChunk(
        id: 'd1_p2_c0',
        docId: 'd1',
        docTitle: 'Calculus',
        pageNumber: 2,
        chunkIndex: 0,
        content: 'Integral is the area under the curve.',
      );

      final progressUpdates = <(int, int)>[];
      await repository.addChunks([
        chunk1,
        chunk2,
      ], onProgress: (current, total) => progressUpdates.add((current, total)));

      expect(fakeEdgeAi.initRagCount, equals(1));
      expect(fakeEdgeAi.addedChunks, equals([chunk1, chunk2]));
      expect(progressUpdates, equals([(1, 2), (2, 2)]));

      fakeEdgeAi.searchResults = const [
        RetrievedChunk(chunk: chunk1, similarityScore: 0.91),
      ];
      final results = await repository.search(query: 'What is a derivative?');
      expect(results, hasLength(1));
      expect(results.first.chunk, equals(chunk1));
    });

    test(
      'removeDocumentChunks forwards chunkIds to EdgeAiRagService.removeChunks',
      () async {
        await repository.removeDocumentChunks('d1', ['d1_p1_c0', 'd1_p2_c0']);
        expect(fakeEdgeAi.removedChunkIds, equals(['d1_p1_c0', 'd1_p2_c0']));
      },
    );

    test('wraps underlying service errors into RagIndexException', () async {
      fakeEdgeAi.error = StateError('SQLite vec0 failure');

      await expectLater(
        () => repository.initialize(),
        throwsA(isA<RagIndexException>()),
      );
    });
  });
}
