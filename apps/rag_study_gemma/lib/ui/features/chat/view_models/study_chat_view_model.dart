import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/chat_role.dart';
import '../../../../domain/models/citation.dart';
import '../../../../domain/use_cases/build_study_prompt_use_case.dart';
import '../../../../domain/use_cases/retrieve_relevant_chunks_use_case.dart';
import '../../../providers/repository_providers.dart';

/// Holds the currently selected document filter for grounded RAG search.
///
/// `null` means search across all indexed study PDFs; a non-null `docId`
/// restricts semantic retrieval to that specific PDF.
class SelectedDocumentFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void selectDocument(String? docId) {
    state = docId;
  }
}

final selectedDocumentFilterProvider =
    NotifierProvider<SelectedDocumentFilterNotifier, String?>(
      SelectedDocumentFilterNotifier.new,
    );

/// Drives the StudyGemma grounded RAG conversation.
///
/// Deliberately NOT `.autoDispose` (see ADR 0004): initializing
/// `EmbeddingGemma 2` + `study_gemma_rag.sqlite` (`RagIndex`) and
/// `Gemma 3 1B IT` is expensive, so this ViewModel remains warm in memory
/// across tab switches between `PDF Library` and `Study Chat`.
class StudyChatViewModel extends AsyncNotifier<List<ChatMessage>> {
  static const _retrieveRelevantChunksUseCase = RetrieveRelevantChunksUseCase();
  static const _buildStudyPromptUseCase = BuildStudyPromptUseCase();

  bool _isGenerating = false;

  @override
  Future<List<ChatMessage>> build() async {
    await ref.watch(ragIndexRepositoryProvider).initialize();
    await ref.watch(chatEngineRepositoryProvider).initialize();
    return ref.watch(chatHistoryRepositoryProvider).getAll();
  }

  /// Sends [questionText] as a new user turn, retrieves top-K PDF chunks
  /// from `RagIndexRepository` (optionally filtered by
  /// [selectedDocumentFilterProvider]), builds a grounded bilingual prompt,
  /// streams tokens from `ChatEngineRepository`, and persists the completed turn.
  Future<void> sendMessage(String questionText) async {
    final trimmed = questionText.trim();
    if (trimmed.isEmpty) return;

    final currentMessages = state.value ?? const <ChatMessage>[];
    if (_isGenerating || currentMessages.any((m) => m.isStreaming)) {
      return;
    }

    _isGenerating = true;
    try {
      final now = DateTime.now();
      final userMessage = ChatMessage(
        id: _generateId('user'),
        role: ChatRole.user,
        text: trimmed,
        createdAt: now,
      );

      // Append user message immediately before async retrieval/generation.
      state = AsyncData([...currentMessages, userMessage]);

      final filterDocId = ref.read(selectedDocumentFilterProvider);
      final docs = await ref
          .read(documentIngestionRepositoryProvider)
          .getAllDocuments();
      final rawRetrieved = await _retrieveRelevantChunksUseCase(
        query: trimmed,
        ragIndexRepository: ref.read(ragIndexRepositoryProvider),
        topK: 8,
        minSimilarity: 0.05,
        filterDocId: filterDocId,
      );
      final retrievedChunks = _buildStudyPromptUseCase.selectBestChunks(
        rawRetrieved,
        maxChunks: 3,
      );

      final citations = [
        for (final retrieved in retrievedChunks)
          Citation(
            id: retrieved.chunk.id,
            docId: retrieved.chunk.docId,
            docTitle: retrieved.chunk.docTitle,
            pageNumber: retrieved.chunk.pageNumber,
            snippet: retrieved.chunk.content,
            similarityScore: retrieved.similarityScore,
          ),
      ];

      final prompt = _buildStudyPromptUseCase(
        userQuestion: trimmed,
        retrievedChunks: retrievedChunks,
        availableDocuments: docs,
      );

      final assistantId = _generateId('assistant');
      var assistantMessage = ChatMessage(
        id: assistantId,
        role: ChatRole.assistant,
        text: '',
        createdAt: DateTime.now(),
        citations: citations,
        isStreaming: true,
      );
      state = AsyncData([...currentMessages, userMessage, assistantMessage]);

      void updateAssistantMessage(String text, {required bool isStreaming}) {
        assistantMessage = assistantMessage.copyWith(
          text: text,
          isStreaming: isStreaming,
        );
        state = AsyncData([...currentMessages, userMessage, assistantMessage]);
      }

      final buffer = StringBuffer();
      final chatEngineRepository = ref.read(chatEngineRepositoryProvider);
      try {
        await for (final token in chatEngineRepository.sendMessage(prompt)) {
          buffer.write(token);
          updateAssistantMessage(buffer.toString(), isStreaming: true);
        }
        updateAssistantMessage(buffer.toString(), isStreaming: false);
      } catch (e, st) {
        debugPrint('[StudyChatViewModel] sendMessage error: $e\n$st');
        final fallbackText = buffer.isEmpty
            ? 'Unable to complete response generation.'
            : buffer.toString();
        updateAssistantMessage(fallbackText, isStreaming: false);
      }

      final chatHistoryRepository = ref.read(chatHistoryRepositoryProvider);
      await chatHistoryRepository.append(userMessage);
      await chatHistoryRepository.append(assistantMessage);
    } finally {
      _isGenerating = false;
    }
  }

  /// Clears persisted chat history and resets the on-device conversation state.
  Future<void> clearHistory() async {
    await ref.read(chatHistoryRepositoryProvider).clear();
    await ref.read(chatEngineRepositoryProvider).resetConversation();
    state = const AsyncData([]);
  }

  String _generateId(String suffix) =>
      '${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

/// Deliberately NOT `.autoDispose` (see ADR 0004) so the loaded Gemma 3 1B IT
/// engine and `RagIndex` stay warm across tab switches.
final studyChatViewModelProvider =
    AsyncNotifierProvider<StudyChatViewModel, List<ChatMessage>>(
      StudyChatViewModel.new,
      retry: (retryCount, error) => null,
    );
