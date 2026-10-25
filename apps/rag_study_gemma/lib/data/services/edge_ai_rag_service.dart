import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_embeddings/flutter_edge_ai_embeddings.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_rag/flutter_edge_ai_rag.dart';
import 'package:flutter_edge_ai_sqlite/flutter_edge_ai_sqlite.dart';

import '../../domain/models/document_chunk.dart';
import '../../domain/models/retrieved_chunk.dart';

/// Unified wrapper around `flutter_edge_ai`, `flutter_edge_ai_litertlm`,
/// `flutter_edge_ai_embeddings`, `flutter_edge_ai_rag`, and
/// `flutter_edge_ai_sqlite`.
///
/// **This is the ONLY file in StudyGemma permitted to import the
/// `flutter_edge_ai*` packages** (see ADR 0001 and ADR 0002).
abstract interface class EdgeAiRagService {
  Future<void> ensureRuntimeInitialized();

  Future<void> initializeRagIndex({
    required String embeddingModelPath,
    required String sqliteDbPath,
  });

  Future<void> addDocumentChunk(DocumentChunk chunk);

  Future<List<RetrievedChunk>> searchChunks({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  });

  Future<void> removeChunks(List<String> chunkIds);

  Future<void> disposeRagIndex();

  Future<void> initializeLlm({required String llmModelPath});

  Stream<String> sendMessageStream(String prompt);

  Future<void> resetConversation();

  Future<void> disposeLlm();
}

/// Production implementation managing the single shared `RagIndex`,
/// `EmbeddingModel` (`EmbeddingGemma 2`), and `InferenceModel` (`Gemma 3 1B IT`).
class EdgeAiRagServiceImpl implements EdgeAiRagService {
  EdgeAiRagServiceImpl({this.backendFallback = true});

  static const String embeddingProfileId =
      'embeddinggemma2-litertlm-text-4410a540ce75-prefix-v1';

  static const String _systemInstruction =
      'You are StudyGemma, an expert offline study companion. '
      'Always answer in the same language as the student question and cite '
      'the provided PDF excerpts using [Doc Title, p. X]. '
      'Be concise (at most 5 bullet points or 1 short paragraph) and never '
      'repeat sentences, phrases, or bullet points.';

  static const int maxResponseChars = 1600;

  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _citationPattern = RegExp(r'\[[^\]]*\]');

  final bool backendFallback;

  bool _runtimeInitialized = false;
  EmbeddingModel? _embedder;
  RagIndex? _ragIndex;
  InferenceModel? _llmModel;
  InferenceChat? _chat;

  @override
  Future<void> ensureRuntimeInitialized() async {
    if (_runtimeInitialized) return;
    await FlutterEdgeAi.initialize(
      inferenceEngines: [LiteRtLmEngine(backendFallback: backendFallback)],
      embeddingBackends: const [LiteRtEmbeddingBackend()],
      embeddingTokenizers: const [GemmaEmbeddingTokenizers()],
    );
    _runtimeInitialized = true;
  }

  @override
  Future<void> initializeRagIndex({
    required String embeddingModelPath,
    required String sqliteDbPath,
  }) async {
    if (_ragIndex != null && !_ragIndex!.isDisposed) return;

    await ensureRuntimeInitialized();

    await FlutterEdgeAi.installEmbedder()
        .modelFromFile(embeddingModelPath)
        .install();

    _embedder = await FlutterEdgeAi.getActiveEmbedder(
      preferredBackend: PreferredBackend.cpu,
    );

    final ragEmbedder = FlutterEdgeAiActiveEmbedder(
      profileId: embeddingProfileId,
    );
    final rag = FlutterEdgeAiRag(
      providers: const [SqliteVectorStoreProvider()],
    );

    _ragIndex = await rag.open(
      spec: VectorStoreSpec(
        providerId: SqliteVectorStoreProvider.providerId,
        location: sqliteDbPath,
        filterSchema: FilterSchema(
          fields: [
            FilterField(name: 'doc_id', type: FilterFieldType.string),
            FilterField(name: 'doc_title', type: FilterFieldType.string),
            FilterField(name: 'page_number', type: FilterFieldType.number),
            FilterField(name: 'chunk_index', type: FilterFieldType.number),
          ],
        ),
      ),
      embedder: ragEmbedder,
    );
  }

  @override
  Future<void> addDocumentChunk(DocumentChunk chunk) async {
    final index = _ragIndex;
    if (index == null || index.isDisposed) {
      throw StateError(
        'EdgeAiRagServiceImpl.initializeRagIndex() must complete before addDocumentChunk().',
      );
    }

    await index.add(
      id: chunk.id,
      document: EmbeddingInput.text(chunk.content),
      content: chunk.content,
      metadata: jsonEncode({
        'doc_id': chunk.docId,
        'doc_title': chunk.docTitle,
        'page_number': chunk.pageNumber,
        'chunk_index': chunk.chunkIndex,
      }),
    );
  }

  @override
  Future<List<RetrievedChunk>> searchChunks({
    required String query,
    int topK = 4,
    double minSimilarity = 0.25,
    String? filterDocId,
  }) async {
    final index = _ragIndex;
    if (index == null || index.isDisposed) {
      throw StateError(
        'EdgeAiRagServiceImpl.initializeRagIndex() must complete before searchChunks().',
      );
    }

    final filter = filterDocId != null
        ? Filter(
            must: [FieldEquals(key: 'doc_id', value: filterDocId)],
          )
        : null;

    final hits = await index.search(
      query: EmbeddingInput.text(query),
      topK: topK,
      threshold: minSimilarity,
      filter: filter,
    );

    return hits.map((hit) {
      final rawMeta = hit.metadata;
      final decoded = rawMeta != null && rawMeta.isNotEmpty
          ? (jsonDecode(rawMeta) as Map<String, Object?>)
          : const <String, Object?>{};
      return RetrievedChunk(
        chunk: DocumentChunk(
          id: hit.id,
          docId: (decoded['doc_id'] as String?) ?? '',
          docTitle: (decoded['doc_title'] as String?) ?? '',
          pageNumber: (decoded['page_number'] as num?)?.toInt() ?? 1,
          chunkIndex: (decoded['chunk_index'] as num?)?.toInt() ?? 0,
          content: hit.content,
        ),
        similarityScore: hit.similarity,
      );
    }).toList();
  }

  @override
  Future<void> removeChunks(List<String> chunkIds) async {
    final index = _ragIndex;
    if (index == null || index.isDisposed) {
      throw StateError(
        'EdgeAiRagServiceImpl.initializeRagIndex() must complete before removeChunks().',
      );
    }

    for (final chunkId in chunkIds) {
      await index.remove(id: chunkId);
    }
  }

  @override
  Future<void> disposeRagIndex() async {
    final index = _ragIndex;
    _ragIndex = null;
    if (index != null && !index.isDisposed) {
      await index.dispose();
    }

    final embedder = _embedder;
    _embedder = null;
    if (embedder != null) {
      await embedder.close();
    }
  }

  @override
  Future<void> initializeLlm({required String llmModelPath}) async {
    if (_llmModel != null) return;

    await ensureRuntimeInitialized();

    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(llmModelPath).install();

    _llmModel = await FlutterEdgeAi.getActiveModel(
      maxTokens: 2048,
      preferredBackend: PreferredBackend.cpu,
    );
  }

  @override
  Stream<String> sendMessageStream(String prompt) async* {
    final model = _llmModel;
    if (model == null) {
      throw StateError(
        'EdgeAiRagServiceImpl.initializeLlm() must complete before sendMessageStream().',
      );
    }

    final previousChat = _chat;
    _chat = null;
    if (previousChat != null) {
      await previousChat.close();
    }

    final chat = await model.createChat(
      systemInstruction: _systemInstruction,
      temperature: 0.3,
      topK: 40,
      topP: 0.9,
      maxOutputTokens: 420,
      enableThinking: false,
    );
    _chat = chat;

    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    final accumulated = StringBuffer();
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse && response.token.isNotEmpty) {
        final candidate = '$accumulated${response.token}';
        if (candidate.length > maxResponseChars ||
            hasRepetitionLoop(candidate)) {
          break;
        }
        accumulated.write(response.token);
        yield response.token;
      }
    }
  }

  /// Deterministic guard detecting tandem phrase repetition or repeated
  /// 48-character clauses (ignoring `[...]` citation tags).
  static bool hasRepetitionLoop(String text) {
    final normalized = text.replaceAll(_whitespacePattern, ' ').trim();
    if (normalized.length < 24) return false;

    final withoutCitations = normalized
        .replaceAll(_citationPattern, '')
        .replaceAll(_whitespacePattern, ' ')
        .trim();

    if (_hasTandemSuffixLoop(normalized) ||
        _hasTandemSuffixLoop(withoutCitations)) {
      return true;
    }

    if (withoutCitations.length >= 160) {
      final prefixEnd = withoutCitations.length - 48;
      final tail = withoutCitations.substring(prefixEnd);
      final priorText = withoutCitations.substring(0, prefixEnd);
      final firstIdx = priorText.indexOf(tail);
      if (firstIdx != -1 && priorText.indexOf(tail, firstIdx + 1) != -1) {
        return true;
      }
    }

    return false;
  }

  static bool _hasTandemSuffixLoop(String s) {
    final n = s.length;
    // Check 1a: 3x consecutive phrase of length 8..80 at the end of s.
    for (var len = 8; len <= 80 && n >= 3 * len; len++) {
      final tail = s.substring(n - len, n);
      final mid = s.substring(n - 2 * len, n - len);
      if (mid == tail) {
        final head = s.substring(n - 3 * len, n - 2 * len);
        if (head == tail) {
          return true;
        }
      }
    }

    // Check 1b: 2x consecutive phrase of length 32..120 at the end of s
    // (either directly adjacent or separated by a single space).
    for (var len = 32; len <= 120 && n >= 2 * len; len++) {
      final tail = s.substring(n - len, n);
      if (s.substring(n - 2 * len, n - len) == tail) {
        return true;
      }
      if (n >= 2 * len + 1 &&
          s[n - len - 1] == ' ' &&
          s.substring(n - 2 * len - 1, n - len - 1) == tail) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<void> resetConversation() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      await chat.close();
    }
  }

  @override
  Future<void> disposeLlm() async {
    await resetConversation();
    final model = _llmModel;
    _llmModel = null;
    if (model != null) {
      await model.close();
    }
  }
}
