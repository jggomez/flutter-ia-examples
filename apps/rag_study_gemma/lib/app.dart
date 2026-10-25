import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/models/model_download_status.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/features/chat/views/study_chat_screen.dart';
import 'ui/features/library/views/document_library_screen.dart';
import 'ui/features/setup/view_models/model_download_view_model.dart';
import 'ui/features/setup/views/model_download_screen.dart';

/// Root Material 3 application widget for StudyGemma.
class StudyGemmaApp extends StatelessWidget {
  const StudyGemmaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudyGemma',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const StudyGemmaHomeShell(),
    );
  }
}

/// Top-level adaptive shell that gates access behind [ModelDownloadScreen]
/// until both on-device models (`EmbeddingGemma 2` + `Gemma 3 1B IT`) report
/// [ModelDownloadPhase.ready], then renders the 2-tab `NavigationBar`
/// (`PDF Library` and `Study Chat`).
class StudyGemmaHomeShell extends ConsumerStatefulWidget {
  const StudyGemmaHomeShell({super.key});

  @override
  ConsumerState<StudyGemmaHomeShell> createState() =>
      _StudyGemmaHomeShellState();
}

class _StudyGemmaHomeShellState extends ConsumerState<StudyGemmaHomeShell> {
  int _selectedTabIndex = 0;

  void _switchToChatTab() {
    setState(() {
      _selectedTabIndex = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloadState = ref.watch(modelDownloadViewModelProvider);

    final isReady = downloadState.maybeWhen(
      data: (status) => status.phase == ModelDownloadPhase.ready,
      orElse: () => false,
    );

    if (!isReady) {
      return const ModelDownloadScreen();
    }

    return Scaffold(
      body: _selectedTabIndex == 0
          ? DocumentLibraryScreen(onNavigateToChat: _switchToChatTab)
          : const StudyChatScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books_rounded),
            label: 'PDF Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Study Chat',
          ),
        ],
      ),
    );
  }
}
