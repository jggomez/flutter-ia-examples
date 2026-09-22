import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/chat_message.dart';
import '../../../../domain/models/chat_role.dart';
import '../../../../domain/models/citation.dart';
import '../../../core/widgets/citation_chip.dart';
import '../../agenda/views/talk_detail_screen.dart';
import '../view_models/chat_view_model.dart';

/// The chat thread UI: message list (user questions right-aligned,
/// assistant answers left-aligned with `CitationChip`s underneath when
/// `ChatMessage.citations` is non-empty) plus a text input calling
/// `ChatViewModel.sendMessage`.
///
/// Only mounted once `ChatTabRoot` has confirmed the model is
/// `ModelDownloadPhase.ready` — this screen never itself checks download
/// status.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: SafeArea(
        child: state.when(
          data: (messages) => _ChatBody(messages: messages),
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
  const _ChatBody({required this.messages});

  final List<ChatMessage> messages;

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(chatViewModelProvider.notifier).sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(
                  key: ValueKey('chatEmpty'),
                  child: Text('Ask a question about the agenda.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) =>
                      _MessageBubble(message: widget.messages[index]),
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chatInputField'),
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Ask about the agenda…',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                key: const ValueKey('chatSendButton'),
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(message.text.isEmpty ? '…' : message.text),
          ),
          if (!isUser && message.citations.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final citation in message.citations)
                  CitationChip(
                    citation: citation,
                    onTap: () => _openTalk(context, citation),
                  ),
              ],
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
