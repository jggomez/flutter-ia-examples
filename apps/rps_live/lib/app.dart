import 'package:flutter/material.dart';

import 'ui/features/history/views/history_screen.dart';
import 'ui/features/practice/views/practice_screen.dart';
import 'ui/features/vs_ai/views/vs_ai_screen.dart';

/// App root. Deliberately minimal: routing between "Tú vs. IA",
/// "Práctica libre" and "Historial" is a `flutter-implementer` concern, not
/// an architectural one, beyond keeping each screen under
/// `ui/features/<feature>/views/`.
///
/// [ProviderScope] (see `main.dart`) wraps this widget so every
/// `ui/features/**` screen can `ref.watch(...)` the providers under
/// `ui/providers/`.
class RpsLiveApp extends StatelessWidget {
  const RpsLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RPS Live',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const _HomeTabs(),
    );
  }
}

/// Simple bottom-navigation shell linking the three top-level screens.
///
/// `_selectedIndex` is purely ephemeral, local UI state (which tab is
/// visible) — kept as `setState` per the ADR's rule that local widget state
/// stays local regardless of the app-wide state management choice.
class _HomeTabs extends StatefulWidget {
  const _HomeTabs();

  @override
  State<_HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<_HomeTabs> {
  int _selectedIndex = 0;

  // Only one of "Tú vs. IA" / "Práctica libre" builds at a time (a plain
  // indexed lookup, not an `IndexedStack`, which would keep every tab's
  // widget subtree — and its view model, and the single shared camera it
  // starts via `classifierRepositoryProvider` — alive simultaneously).
  // `VsAiViewModel`/`PracticeViewModel` both `initialize()` the camera on
  // build and `dispose()` it when torn down, so leaving the previous tab
  // mounted would mean two view models fighting over one camera.
  static const _screens = [VsAiScreen(), PracticeScreen(), HistoryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_kabaddi),
            label: 'Tú vs. IA',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt),
            label: 'Práctica',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historial'),
        ],
      ),
    );
  }
}
