import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../../setup/view_models/model_download_view_model.dart';
import '../../setup/views/model_setup_screen.dart';
import 'chat_screen.dart';

/// Root widget for the "Chat" tab: watches
/// `modelDownloadViewModelProvider` and shows [ModelSetupScreen] until the
/// model reaches `ModelDownloadPhase.ready`, then swaps to [ChatScreen] —
/// the lazy, "triggered when the user opens the Chat tab" download flow
/// described in `doc/adr/0005-model-download-flow.md`.
///
/// This widget is the seam between the setup and chat features; neither
/// `ModelSetupScreen` nor `ChatScreen` needs to know about the other's
/// provider.
class ChatTabRoot extends ConsumerWidget {
  const ChatTabRoot({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelDownloadViewModelProvider);
    return state.when(
      data: (status) => status.phase == ModelDownloadPhase.ready
          ? ChatScreen(initialPrompt: initialPrompt)
          : const ModelSetupScreen(),
      loading: () => const Scaffold(
        body: Center(
          key: ValueKey('chatTabRootLoading'),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stackTrace) => Scaffold(
        body: Center(
          key: const ValueKey('chatTabRootError'),
          child: Text('Error: $error', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
