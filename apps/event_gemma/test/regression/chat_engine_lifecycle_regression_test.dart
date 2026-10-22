// Regression coverage pinning `doc/adr/0003-state-management-riverpod.md`'s
// documented exception: `chatViewModelProvider` is deliberately NOT
// `.autoDispose`, because this app has exactly ONE consumer of
// `ChatEngineRepository` (unlike `apps/rps_live`'s `ClassifierRepository`,
// shared across two `.autoDispose` screens racing initialize()/dispose() on
// tab switch — see that app's `test/regression/classifier_lifecycle_regression_test.dart`,
// which proves the OPPOSITE property: that reference counting is needed
// there). This test proves the property this app's design relies on
// instead: the engine's `initialize()` runs exactly once per app session,
// even across a tab-away/tab-back cycle on `chatViewModelProvider`, because
// the provider itself is never torn down between visits.
import 'package:event_gemma/domain/models/chat_message.dart';
import 'package:event_gemma/ui/features/chat/view_models/chat_view_model.dart';
import 'package:event_gemma/ui/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  test('chatViewModelProvider initializes the engine exactly once across '
      'simulated tab-away/tab-back reads (it is NOT .autoDispose, unlike '
      'every other feature view-model provider in this app)', () async {
    final engine = FakeChatEngineRepository();
    final container = ProviderContainer(
      overrides: [
        chatEngineRepositoryProvider.overrideWithValue(engine),
        agendaRepositoryProvider.overrideWithValue(FakeAgendaRepository()),
        chatHistoryRepositoryProvider.overrideWithValue(
          FakeChatHistoryRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // First "visit" to the Chat tab: reading the provider triggers build(),
    // which initializes the engine.
    List<ChatMessage> first = await container.read(
      chatViewModelProvider.future,
    );
    expect(first, isEmpty);
    expect(engine.initializeCallCount, 1);

    // Simulate navigating away to the Agenda tab: nothing here disposes
    // `chatViewModelProvider` (unlike an `.autoDispose` provider, which
    // would tear down — and re-`initialize()` on return — once its last
    // widget listener is gone). A bare `container.read` with no active
    // listener is exactly that "no one is watching it right now" state.
    await _flushMicrotasks();
    await _flushMicrotasks();

    // "Tab back" to Chat: reading the same provider again must NOT re-run
    // build()/re-initialize the engine — it should just return the
    // already-resolved state instantly, proving the provider (and the
    // engine it initialized) survived the simulated tab switch.
    final second = await container.read(chatViewModelProvider.future);
    expect(second, isEmpty);
    expect(
      engine.initializeCallCount,
      1,
      reason:
          'chatViewModelProvider is deliberately NOT .autoDispose (see '
          'doc/adr/0003-state-management-riverpod.md) — the engine must '
          'load once per app session, not once per Chat-tab visit.',
    );

    // Repeat the cycle a few more times for good measure — still exactly
    // one initialize() call across the whole simulated session.
    for (var i = 0; i < 3; i++) {
      await _flushMicrotasks();
      await container.read(chatViewModelProvider.future);
    }
    expect(engine.initializeCallCount, 1);
    expect(engine.disposeCallCount, 0);
  });

  testWidgets('the same property holds when driven through real widget '
      'mount/unmount cycles switching between two tabs, one of which reads '
      'chatViewModelProvider', (tester) async {
    final engine = FakeChatEngineRepository();
    final container = ProviderContainer(
      overrides: [
        chatEngineRepositoryProvider.overrideWithValue(engine),
        agendaRepositoryProvider.overrideWithValue(FakeAgendaRepository()),
        chatHistoryRepositoryProvider.overrideWithValue(
          FakeChatHistoryRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _TabsReadingChatViewModel()),
      ),
    );
    await tester.pump();
    expect(engine.initializeCallCount, 1);

    // Switch away from the tab that watches chatViewModelProvider...
    await tester.tap(find.byKey(const ValueKey('switchTab')));
    await tester.pump();
    await tester.pump();
    // ...and back.
    await tester.tap(find.byKey(const ValueKey('switchTab')));
    await tester.pump();
    await tester.pump();

    expect(
      engine.initializeCallCount,
      1,
      reason:
          'a non-.autoDispose provider must not be rebuilt just because '
          'its widget was unmounted and remounted.',
    );
  });
}

/// Minimal stand-in for `app.dart`'s tab shell: one tab watches
/// `chatViewModelProvider` (mirroring `ChatTabRoot`/`ChatScreen`), the
/// other is an unrelated placeholder (mirroring `AgendaListScreen`).
class _TabsReadingChatViewModel extends StatefulWidget {
  const _TabsReadingChatViewModel();

  @override
  State<_TabsReadingChatViewModel> createState() =>
      _TabsReadingChatViewModelState();
}

class _TabsReadingChatViewModelState extends State<_TabsReadingChatViewModel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _index == 0 ? const _ChatTabWatcher() : const Text('Agenda'),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('switchTab'),
        onPressed: () => setState(() => _index = 1 - _index),
        child: const Icon(Icons.swap_horiz),
      ),
    );
  }
}

class _ChatTabWatcher extends ConsumerWidget {
  const _ChatTabWatcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatViewModelProvider);
    return Text('chat: $state');
  }
}
