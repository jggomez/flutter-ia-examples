import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/chat_role.dart';
import '../../../../domain/models/citation.dart';
import '../../../core/widgets/citation_chip.dart';
import '../../agenda/views/talk_detail_screen.dart';
import '../view_models/chat_view_model.dart';

/// The chat thread UI: modern asymmetric bubbles, prompt suggestion pills,
/// pulsing 3-dot generation indicators, enhanced citation pills, and a floating
/// rounded message bar.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatViewModelProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 20),
            SizedBox(width: 8),
            Text('AI Assistant'),
          ],
        ),
      ),
      body: SafeArea(
        child: state.when(
          data: (messages) =>
              _ChatBody(messages: messages, initialPrompt: initialPrompt),
          loading: () => const Center(
            key: ValueKey('chatLoading'),
            child: CircularProgressIndicator(),
          ),
          error: (error, stackTrace) => Center(
            key: const ValueKey('chatError'),
            child: Text('Error: $error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody({required this.messages, this.initialPrompt});

  final List<ChatMessage> messages;
  final String? initialPrompt;

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasText = false;

  static const _promptSuggestions = [
    'What are the keynote sessions?',
    'Summarize Day 1 Flutter talks',
    'Which sessions cover on-device Gemma?',
    'Show me talks on LiteRT',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      _controller.text = widget.initialPrompt!;
      _hasText = true;
    }
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatViewModelProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _sendPrompt(String prompt) {
    _controller.text = prompt;
    _send();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? _EmptyState(
                  suggestions: _promptSuggestions,
                  onSelectSuggestion: _sendPrompt,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: widget.messages[index]),
                ),
        ),
        // Floating rounded input bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant.withAlpha(128)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(140),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chatInputField'),
                          controller: _controller,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Ask about any talk, speaker, or track…',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      if (_hasText)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _hasText = false);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('chatSendButton'),
                onPressed: _send,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                  minimumSize: const Size(48, 48),
                ),
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.suggestions,
    required this.onSelectSuggestion,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelectSuggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      key: const ValueKey('chatEmpty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withAlpha(40),
                    colorScheme.secondary.withAlpha(40),
                  ],
                ),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Conference AI Assistant',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask anything about sessions, speakers, schedule, or topics. Powered 100% on-device by Gemma 3.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'Suggested questions',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final prompt in suggestions)
                  ActionChip(
                    avatar: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    label: Text(prompt),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    backgroundColor: colorScheme.surfaceContainerLow,
                    side: BorderSide(color: colorScheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: () => onSelectSuggestion(prompt),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.role == ChatRole.user;
    final isGenerating = !isUser && message.text.isEmpty;

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
              radius: 14,
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(
                Icons.auto_awesome,
                size: 14,
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
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest.withAlpha(200),
                    borderRadius: isUser
                        ? const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(4),
                          )
                        : const BorderRadius.only(
                            topLeft: Radius.circular(18),
                            topRight: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                            bottomLeft: Radius.circular(4),
                          ),
                    border: isUser
                        ? null
                        : Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: isGenerating
                      ? const _GenerationDotsIndicator(
                          key: ValueKey('assistantGeneratingIndicator'),
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
                        CitationChip(
                          citation: citation,
                          onTap: () => _openTalk(context, citation),
                        ),
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

  void _openTalk(BuildContext context, Citation citation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TalkDetailScreen(talkId: citation.talkId),
      ),
    );
  }
}

/// Pulsing 3-dot animation displayed while the assistant answer is generating.
class _GenerationDotsIndicator extends StatefulWidget {
  const _GenerationDotsIndicator({super.key});

  @override
  State<_GenerationDotsIndicator> createState() =>
      _GenerationDotsIndicatorState();
}

class _GenerationDotsIndicatorState extends State<_GenerationDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildDot(int index, Color color) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final progress = (_animController.value - (index * 0.2)) % 1.0;
        final scale = 0.5 + 0.5 * (1.0 - (progress - 0.5).abs() * 2);
        final opacity = 0.4 + 0.6 * (1.0 - (progress - 0.5).abs() * 2);

        return Opacity(
          opacity: opacity.clamp(0.2, 1.0),
          child: Transform.scale(
            scale: scale.clamp(0.6, 1.2),
            child: Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDot(0, dotColor),
          _buildDot(1, dotColor),
          _buildDot(2, dotColor),
        ],
      ),
    );
  }
}
