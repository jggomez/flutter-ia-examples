import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/chat_role.dart';
import '../../../../domain/models/study_document.dart';
import '../../../core/widgets/citation_chip.dart';
import '../../library/view_models/document_library_view_model.dart';
import '../view_models/study_chat_view_model.dart';

/// Grounded Study Chat screen with top document filter ChoiceChips,
/// study prompt suggestions, streaming assistant cards, and interactive
/// `[Doc Title · p. N]` CitationChips.
class StudyChatScreen extends ConsumerWidget {
  const StudyChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(studyChatViewModelProvider);
    final libraryState = ref.watch(documentLibraryViewModelProvider);
    final documents = libraryState.value?.documents ?? const <StudyDocument>[];
    final selectedDocId = ref.watch(selectedDocumentFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.psychology_rounded, size: 22),
            SizedBox(width: 10),
            Text('StudyGemma Chat'),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('clearChatHistoryButton'),
            tooltip: 'Clear chat history',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () =>
                ref.read(studyChatViewModelProvider.notifier).clearHistory(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _DocumentFilterBar(
              documents: documents,
              selectedDocId: selectedDocId,
              onSelectDocId: (docId) => ref
                  .read(selectedDocumentFilterProvider.notifier)
                  .selectDocument(docId),
            ),
            Expanded(
              child: chatState.when(
                data: (messages) => _StudyChatBody(messages: messages),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    key: ValueKey('studyChatLoading'),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error initializing Study Chat: $error',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentFilterBar extends StatelessWidget {
  const _DocumentFilterBar({
    required this.documents,
    required this.selectedDocId,
    required this.onSelectDocId,
  });

  final List<StudyDocument> documents;
  final String? selectedDocId;
  final ValueChanged<String?> onSelectDocId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              key: const ValueKey('filterChip_all'),
              label: const Text('All PDFs'),
              selected: selectedDocId == null,
              onSelected: (_) => onSelectDocId(null),
            ),
            for (final doc in documents) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                key: ValueKey('filterChip_${doc.id}'),
                label: Text(doc.title),
                selected: selectedDocId == doc.id,
                onSelected: (_) => onSelectDocId(doc.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudyChatBody extends ConsumerStatefulWidget {
  const _StudyChatBody({required this.messages});

  final List<ChatMessage> messages;

  @override
  ConsumerState<_StudyChatBody> createState() => _StudyChatBodyState();
}

class _StudyChatBodyState extends ConsumerState<_StudyChatBody> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const List<String> _promptSuggestions = [
    'Summarize the main concepts',
    'Create 3 quiz questions from this PDF',
    'What are the key definitions?',
  ];

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isGenerating => widget.messages.any((m) => m.isStreaming);

  void _sendCurrentText() {
    if (_isGenerating) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    ref.read(studyChatViewModelProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _sendSuggestion(String prompt) {
    if (_isGenerating) return;
    ref.read(studyChatViewModelProvider.notifier).sendMessage(prompt);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGenerating = _isGenerating;

    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? _EmptyStudyChatState(
                  suggestions: _promptSuggestions,
                  isGenerating: isGenerating,
                  onSelectSuggestion: _sendSuggestion,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) =>
                      _StudyMessageBubble(message: widget.messages[index]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chatInputField'),
                  controller: _textController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendCurrentText(),
                  decoration: InputDecoration(
                    hintText: 'Ask a grounded question about your PDFs…',
                    prefixIcon: Icon(
                      Icons.auto_awesome_rounded,
                      size: 19,
                      color: colorScheme.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(26),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Send question',
                child: FilledButton(
                  key: const ValueKey('chatSendButton'),
                  onPressed: isGenerating ? null : _sendCurrentText,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyStudyChatState extends StatelessWidget {
  const _EmptyStudyChatState({
    required this.suggestions,
    required this.isGenerating,
    required this.onSelectSuggestion,
  });

  final List<String> suggestions;
  final bool isGenerating;
  final ValueChanged<String> onSelectSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.school_rounded,
                size: 34,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Grounded PDF Study Companion',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Every answer retrieves top-K vector chunks from SQLite vec0 '
              'and cites the exact PDF document and page number.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    avatar: Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: colorScheme.primary,
                    ),
                    label: Text(suggestion),
                    onPressed: isGenerating
                        ? null
                        : () => onSelectSuggestion(suggestion),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyMessageBubble extends StatelessWidget {
  const _StudyMessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.role == ChatRole.user;
    final showStreamingPlaceholder =
        !isUser && message.isStreaming && message.text.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 15,
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: showStreamingPlaceholder
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Synthesizing cited answer…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          message.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: isUser
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                ),
                if (!isUser && message.citations.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final citation in message.citations)
                        CitationChip(citation: citation),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
