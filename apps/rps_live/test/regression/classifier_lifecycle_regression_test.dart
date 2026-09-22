// Regression coverage for flutter-reviewer's Bug 1 (camera-owning provider
// lifecycle leak): `vsAiViewModelProvider`/`practiceViewModelProvider` were
// plain (non-`.autoDispose`) providers sharing one `ClassifierRepositoryImpl`
// singleton whose `initialize()`/`dispose()` were not safe to call more than
// once. See the addendum to `doc/adr/0001-state-management-riverpod.md`.
//
// Deliberately does NOT use `FakeClassifierRepository` (the repository-level
// fake every other view-model test uses): that fake's `initialize()` is
// trivially idempotent by construction (it just increments a counter), so a
// test built on it can never observe a real leak in
// `ClassifierRepositoryImpl`'s own bookkeeping — which is exactly why this
// bug shipped past the original TDD pass. Instead this composes a REAL
// `ClassifierRepositoryImpl` from *service*-level fakes
// (`FakeCameraFrameService`/`FakeTfliteClassifierService`), the same way
// `main.dart` composes the production instance from
// `CameraFrameServiceImpl`/`TfliteClassifierServiceImpl`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/data/repositories/classifier_repository_impl.dart';
import 'package:rps_live/ui/features/practice/view_models/practice_view_model.dart';
import 'package:rps_live/ui/features/practice/views/practice_screen.dart';
import 'package:rps_live/ui/features/vs_ai/view_models/vs_ai_view_model.dart';
import 'package:rps_live/ui/features/vs_ai/views/vs_ai_screen.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../support/fakes.dart';

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  group('shared ClassifierRepositoryImpl across vs_ai and practice providers', () {
    test('visiting "Tú vs. IA" then "Práctica libre" (dispose before the '
        'next initialize) does not throw and leaves no orphaned camera '
        'subscription or native interpreter, repeated across several '
        'switches', () async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService();
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );
      final container = ProviderContainer(
        overrides: [classifierRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      for (var cycle = 0; cycle < 3; cycle++) {
        // Visit "Tú vs. IA": its `.autoDispose` NotifierProvider is
        // created (build() runs, kicking off
        // `classifierRepository.initialize()`), read without holding a
        // listener alive — exactly like a screen that gets visited and
        // then navigated away from with nothing else watching it.
        expect(() => container.read(vsAiViewModelProvider), returnsNormally);
        await _flushMicrotasks();
        // No active listener kept it alive: Riverpod's `.autoDispose`
        // scheduler tears it down shortly after (a zero-duration timer
        // per provider scope), running `ref.onDispose` ->
        // `classifierRepository.dispose()`. One more flush lets that
        // scheduled disposal (and the fully-microtask-driven fake
        // services' async work inside it) complete.
        await _flushMicrotasks();

        expect(
          camera.listenerCount,
          0,
          reason:
              'leaving "Tú vs. IA" must cancel its frame subscription '
              '(cycle $cycle)',
        );
        expect(
          classifierService.disposeCallCount,
          cycle * 2 + 1,
          reason:
              'leaving "Tú vs. IA" must release the interpreter '
              '(cycle $cycle)',
        );

        // Now visit "Práctica libre" on the SAME shared repository
        // instance — this is what would have thrown/leaked under Bug 1
        // (TfliteClassifierServiceImpl.load() creating a second native
        // Interpreter on top of one never closed, and
        // ClassifierRepositoryImpl.initialize() creating a second frame
        // subscription on top of one never cancelled).
        expect(
          () => container.read(practiceViewModelProvider),
          returnsNormally,
        );
        await _flushMicrotasks();
        await _flushMicrotasks();

        expect(
          camera.listenerCount,
          0,
          reason:
              'leaving "Práctica libre" must cancel its frame '
              'subscription (cycle $cycle)',
        );
        expect(classifierService.disposeCallCount, cycle * 2 + 2);
      }

      // Across 3 full vs_ai<->practice cycles, exactly 6 initialize()/
      // dispose() pairs happened (one per visit) — no accumulation of
      // un-torn-down sessions, and never more than one interpreter/frame
      // subscription alive at a time.
      expect(classifierService.loadCallCount, 6);
      expect(classifierService.disposeCallCount, 6);
      expect(camera.startCallCount, 6);
      expect(camera.stopCallCount, 6);
    });

    testWidgets('switching tabs in a single frame (the incoming screen\'s '
        'initialize() can run before the outgoing screen\'s dispose(), per '
        'Riverpod\'s autoDispose scheduling) keeps the newly-active screen\'s '
        'camera session alive instead of the stale dispose() tearing it '
        'down underneath it', (tester) async {
      final camera = FakeCameraFrameService();
      final classifierService = FakeTfliteClassifierService();
      final repository = ClassifierRepositoryImpl(
        cameraFrameService: camera,
        classifierService: classifierService,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            classifierRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: _Tabs()),
        ),
      );
      await tester.pump();

      expect(classifierService.loadCallCount, 1);
      expect(camera.listenerCount, 1);

      // Switch from "Tú vs. IA" to "Práctica libre" within one frame,
      // exactly like `app.dart`'s indexed-lookup tab navigation.
      await tester.tap(find.byKey(const ValueKey('switchTab')));
      await tester.pump();

      // The practice screen's session must be the one left standing:
      // still exactly one interpreter load / one live frame listener,
      // not zero (which would mean the stale vs_ai dispose() won the
      // race and killed practice's brand-new session).
      expect(
        classifierService.disposeCallCount,
        0,
        reason:
            'the outgoing "Tú vs. IA" dispose() must not tear down the '
            'session "Práctica libre" just started',
      );
      expect(camera.listenerCount, 1);

      // Let any further scheduled autoDispose work settle. Deliberately not
      // `pumpAndSettle()`: "Práctica libre" is (and stays, in this test) in
      // its `AsyncLoading` state, which renders an indeterminate
      // `CircularProgressIndicator` — an infinite animation that would make
      // `pumpAndSettle()` time out.
      await tester.pump();
      await tester.pump();
      expect(classifierService.loadCallCount, 1);
      expect(classifierService.disposeCallCount, 0);
      expect(camera.listenerCount, 1);
    });
  });
}

/// Minimal stand-in for `app.dart`'s `_HomeTabs`: a plain indexed lookup
/// (real widget unmount/remount, not an `IndexedStack`) switching between
/// "Tú vs. IA" and "Práctica libre".
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;
  static const _screens = [VsAiScreen(), PracticeScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('switchTab'),
        onPressed: () => setState(() => _index = 1 - _index),
        child: const Icon(Icons.swap_horiz),
      ),
    );
  }
}
