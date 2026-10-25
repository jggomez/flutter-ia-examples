// ignore_for_file: prefer_initializing_formals

import '../../core/error/app_exception.dart';
import '../../domain/models/document_chunk.dart';
import '../../domain/models/retrieved_chunk.dart';
import '../../domain/repositories/rag_index_repository.dart';
import '../services/app_storage_service.dart';
import '../services/edge_ai_rag_service.dart';

/// Implementation of [RagIndexRepository] backed by [EdgeAiRagService] and
/// [AppStorageService].
class RagIndexRepositoryImpl implements RagIndexRepository {
  RagIndexRepositoryImpl({
    required EdgeAiRagService edgeAiRagService,
    AppStorageService? appStorageService,
  }) : _edgeAiRagService = edgeAiRagService,
       _appStorageService = appStorageService ?? AppStorageServiceImpl();

  final EdgeAiRagService _edgeAiRagService;
  final AppStorageService _appStorageService;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final embeddingPath = await _appStorageService.embeddingModelFilePath;
      final sqlitePath = await _appStorageService.ragSqliteDbPath;
      await _edgeAiRagService.initializeRagIndex(
        embeddingModelPath: embeddingPath,
        sqliteDbPath: sqlitePath,
      );
      _initialized = true;
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RagIndexException(
          'Failed to initialize on-device sqlite-vec RAG index.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> addChunks(
    List<DocumentChunk> chunks, {
    void Function(int current, int total)? onProgress,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }
      final total = chunks.length;
      for (var i = 0; i < total; i++) {
        await _edgeAiRagService.addDocumentChunk(chunks[i]);
        onProgress?.call(i + 1, total);
      }
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RagIndexException(
          'Failed to index document chunks into sqlite-vec store.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<List<RetrievedChunk>> search({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async {
    try {
      if (!_initialized) {
        await initialize();
      }
      return await _edgeAiRagService.searchChunks(
        query: query,
        topK: topK,
        minSimilarity: minSimilarity,
        filterDocId: filterDocId,
      );
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RagIndexException(
          'Failed to query on-device sqlite-vec RAG index.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> removeDocumentChunks(String docId, List<String> chunkIds) async {
    try {
      if (chunkIds.isEmpty) return;
      if (!_initialized) {
        await initialize();
      }
      await _edgeAiRagService.removeChunks(chunkIds);
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RagIndexException(
          'Failed to remove chunks for document $docId from RAG index.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _edgeAiRagService.disposeRagIndex();
    } finally {
      _initialized = false;
    }
  }
}
