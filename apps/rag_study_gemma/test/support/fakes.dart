import 'dart:async';

import 'package:rag_study_gemma/domain/models/chat_message.dart';
import 'package:rag_study_gemma/domain/models/document_chunk.dart';
import 'package:rag_study_gemma/domain/models/ingestion_progress.dart';
import 'package:rag_study_gemma/domain/models/model_download_status.dart';
import 'package:rag_study_gemma/domain/models/retrieved_chunk.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';
import 'package:rag_study_gemma/domain/repositories/chat_engine_repository.dart';
import 'package:rag_study_gemma/domain/repositories/chat_history_repository.dart';
import 'package:rag_study_gemma/domain/repositories/document_ingestion_repository.dart';
import 'package:rag_study_gemma/domain/repositories/model_download_repository.dart';
import 'package:rag_study_gemma/domain/repositories/rag_index_repository.dart';

/// Fake [DocumentIngestionRepository] for unit, widget, and regression tests.
class FakeDocumentIngestionRepository implements DocumentIngestionRepository {
  String? nextPickedPdfPath;
  final List<StudyDocument> documents = [];
  Stream<IngestionProgress>? customIngestStream;
  Object? errorToThrow;
  final List<String> deletedDocIds = [];

  @override
  Future<String?> pickPdfPath() async {
    if (errorToThrow != null) throw errorToThrow!;
    return nextPickedPdfPath;
  }

  @override
  Stream<IngestionProgress> ingestPdf({required String filePath}) {
    if (errorToThrow != null) {
      return Stream<IngestionProgress>.error(errorToThrow!);
    }
    if (customIngestStream != null) {
      return customIngestStream!;
    }
    final doc = StudyDocument(
      id: 'doc_${documents.length + 1}',
      title: filePath.split('/').last.replaceAll('.pdf', ''),
      fileName: filePath.split('/').last,
      filePath: filePath,
      pageCount: 5,
      chunkCount: 12,
      indexedAt: DateTime.utc(2026, 10, 24),
    );
    documents.add(doc);
    return Stream<IngestionProgress>.fromIterable([
      const IngestionProgress(
        stage: IngestionStage.validating,
        current: 0,
        total: 1,
        message: 'Validating PDF header...',
      ),
      const IngestionProgress(
        stage: IngestionStage.extracting,
        current: 5,
        total: 5,
        message: 'Extracted 5 pages.',
      ),
      const IngestionProgress(
        stage: IngestionStage.chunking,
        current: 12,
        total: 12,
        message: 'Created 12 chunks.',
      ),
      const IngestionProgress(
        stage: IngestionStage.embedding,
        current: 12,
        total: 12,
        message: 'Indexed 12 chunks.',
      ),
      IngestionProgress(
        stage: IngestionStage.completed,
        current: 12,
        total: 12,
        message: 'Completed indexing.',
        document: doc,
      ),
    ]);
  }

  @override
  Future<List<StudyDocument>> getAllDocuments() async {
    if (errorToThrow != null) throw errorToThrow!;
    return List<StudyDocument>.unmodifiable(documents);
  }

  @override
  Future<void> deleteDocument(String docId) async {
    if (errorToThrow != null) throw errorToThrow!;
    deletedDocIds.add(docId);
    documents.removeWhere((d) => d.id == docId);
  }
}

/// Fake [RagIndexRepository] for unit, widget, and regression tests.
class FakeRagIndexRepository implements RagIndexRepository {
  int initializeCallCount = 0;
  int disposeCallCount = 0;
  final List<DocumentChunk> indexedChunks = [];
  List<RetrievedChunk> searchResults = [];
  String? lastSearchQuery;
  String? lastFilterDocId;
  int? lastTopK;
  double? lastMinSimilarity;
  Object? errorToThrow;

  @override
  Future<void> initialize() async {
    if (errorToThrow != null) throw errorToThrow!;
    initializeCallCount++;
  }

  @override
  Future<void> addChunks(
    List<DocumentChunk> chunks, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    for (var i = 0; i < chunks.length; i++) {
      indexedChunks.add(chunks[i]);
      onProgress?.call(i + 1, chunks.length);
    }
  }

  @override
  Future<List<RetrievedChunk>> search({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastSearchQuery = query;
    lastTopK = topK;
    lastMinSimilarity = minSimilarity;
    lastFilterDocId = filterDocId;

    var results = searchResults.toList();
    if (filterDocId != null) {
      results = results.where((r) => r.chunk.docId == filterDocId).toList();
    }
    return results;
  }

  @override
  Future<void> removeDocumentChunks(String docId, List<String> chunkIds) async {
    if (errorToThrow != null) throw errorToThrow!;
    indexedChunks.removeWhere(
      (chunk) => chunk.docId == docId || chunkIds.contains(chunk.id),
    );
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

/// Fake [ChatEngineRepository] for unit, widget, and regression tests.
class FakeChatEngineRepository implements ChatEngineRepository {
  int initializeCallCount = 0;
  int resetCallCount = 0;
  int disposeCallCount = 0;
  List<String> responseTokens = const ['Grounded ', 'study ', 'answer.'];
  final List<String> sentPrompts = [];
  Object? errorToThrow;

  @override
  Future<void> initialize() async {
    if (errorToThrow != null) throw errorToThrow!;
    initializeCallCount++;
  }

  @override
  Stream<String> sendMessage(String prompt) {
    if (errorToThrow != null) {
      return Stream<String>.error(errorToThrow!);
    }
    sentPrompts.add(prompt);
    return Stream<String>.fromIterable(responseTokens);
  }

  @override
  Future<void> resetConversation() async {
    if (errorToThrow != null) throw errorToThrow!;
    resetCallCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

/// Fake [ChatHistoryRepository] for unit, widget, and regression tests.
class FakeChatHistoryRepository implements ChatHistoryRepository {
  final List<ChatMessage> messages = [];
  int clearCallCount = 0;
  Object? errorToThrow;

  @override
  Future<List<ChatMessage>> getAll() async {
    if (errorToThrow != null) throw errorToThrow!;
    return List<ChatMessage>.unmodifiable(messages);
  }

  @override
  Future<void> append(ChatMessage message) async {
    if (errorToThrow != null) throw errorToThrow!;
    messages.add(message);
  }

  @override
  Future<void> clear() async {
    if (errorToThrow != null) throw errorToThrow!;
    clearCallCount++;
    messages.clear();
  }
}

/// Fake [ModelDownloadRepository] for unit, widget, and regression tests.
class FakeModelDownloadRepository implements ModelDownloadRepository {
  bool modelsReady = true;
  bool wifiConnected = true;
  String? lastHfToken;
  int deleteModelsCallCount = 0;
  Stream<ModelDownloadStatus>? customDownloadStream;
  Object? errorToThrow;

  @override
  Future<bool> areModelsReady() async {
    if (errorToThrow != null) throw errorToThrow!;
    return modelsReady;
  }

  @override
  Future<bool> isUnmeteredWifi() async {
    if (errorToThrow != null) throw errorToThrow!;
    return wifiConnected;
  }

  @override
  Stream<ModelDownloadStatus> downloadModels({String? hfToken}) {
    lastHfToken = hfToken;
    if (errorToThrow != null) {
      return Stream<ModelDownloadStatus>.error(errorToThrow!);
    }
    if (customDownloadStream != null) {
      return customDownloadStream!;
    }
    if (!wifiConnected) {
      return Stream<ModelDownloadStatus>.value(
        const ModelDownloadStatus(
          phase: ModelDownloadPhase.failed,
          errorMessage: 'Active Wi-Fi connection required to download models.',
        ),
      );
    }
    modelsReady = true;
    return Stream<ModelDownloadStatus>.fromIterable([
      const ModelDownloadStatus(
        phase: ModelDownloadPhase.downloadingEmbedding,
        bytesReceived: 80 * 1024 * 1024,
        totalBytes: 157 * 1024 * 1024,
        currentModelName: 'EmbeddingGemma 2 (270M)',
      ),
      const ModelDownloadStatus(
        phase: ModelDownloadPhase.downloadingLlm,
        bytesReceived: 1290 * 1024 * 1024,
        totalBytes: 2580 * 1024 * 1024,
        currentModelName: 'Gemma 4 E2B IT',
      ),
      const ModelDownloadStatus(
        phase: ModelDownloadPhase.ready,
        bytesReceived: 2580 * 1024 * 1024,
        totalBytes: 2580 * 1024 * 1024,
        currentModelName: 'Gemma 4 E2B IT',
      ),
    ]);
  }

  @override
  Future<void> deleteModels() async {
    if (errorToThrow != null) throw errorToThrow!;
    deleteModelsCallCount++;
    modelsReady = false;
  }
}
