import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/providers/app_providers.dart';
import 'ui/screens/model_download_screen.dart';
import 'ui/screens/pocket_squad_workspace_screen.dart';
import 'ui/theme/pocket_squad_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const PocketSquadApp(),
    ),
  );
}

/// Root Material 3 application for **Pocket Squad: Editorial Luxury Travel & Budget Concierge**.
class PocketSquadApp extends ConsumerWidget {
  const PocketSquadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Pocket Squad — On-Device ADK Travel & Budget Concierge',
      debugShowCheckedModeBanner: false,
      theme: PocketSquadTheme.lightTheme,
      darkTheme: PocketSquadTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const PocketSquadReadinessGate(),
    );
  }
}

/// Readiness gate that checks whether the on-device `gemma-4-E2B-it.litertlm`
/// (2.58 GB) artifact is ready on disk (or LAN mode is active) before
/// entering [PocketSquadWorkspaceScreen].
class PocketSquadReadinessGate extends ConsumerWidget {
  const PocketSquadReadinessGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadViewModel = ref.watch(modelDownloadViewModelProvider);

    return ListenableBuilder(
      listenable: downloadViewModel,
      builder: (context, _) {
        if (downloadViewModel.isReady) {
          return const PocketSquadWorkspaceScreen();
        }
        return const ModelDownloadScreen();
      },
    );
  }
}
