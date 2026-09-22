import 'package:flutter/material.dart';

import 'ui/features/agenda/views/agenda_list_screen.dart';
import 'ui/features/chat/views/chat_tab_root.dart';

/// App root: a 2-tab shell (Agenda / Chat). [ProviderScope] (see
/// `main.dart`) wraps this widget so every `ui/features/**` screen can
/// `ref.watch(...)` the providers under `ui/providers/`.
///
/// Deliberately minimal, mirroring `apps/rps_live/lib/app.dart`: routing
/// polish is a `flutter-implementer` concern, not an architectural one,
/// beyond keeping each screen under `ui/features/<feature>/views/`.
class EventLlmWikiApp extends StatelessWidget {
  const EventLlmWikiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Event LLM-Wiki',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const _HomeTabs(),
    );
  }
}

/// Simple bottom-navigation shell linking the two top-level screens.
///
/// `_selectedIndex` is purely ephemeral, local UI state — kept as
/// `setState` per `doc/adr/0003-state-management-riverpod.md`'s rule that
/// local widget state stays local regardless of the app-wide state
/// management choice.
class _HomeTabs extends StatefulWidget {
  const _HomeTabs();

  @override
  State<_HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<_HomeTabs> {
  int _selectedIndex = 0;

  // A plain indexed lookup (not `IndexedStack`): unlike `apps/rps_live`,
  // neither tab here owns a shared, exclusive hardware resource that needs
  // real unmount semantics to release (the Chat tab's engine is
  // deliberately session-lived — see `chatViewModelProvider`'s non-
  // `.autoDispose` exception), so either widget-mount strategy would be
  // architecturally fine; the indexed lookup is kept for consistency with
  // `apps/rps_live/lib/app.dart`.
  static const _screens = [AgendaListScreen(), ChatTabRoot()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.event_note), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: 'Chat'),
        ],
      ),
    );
  }
}
