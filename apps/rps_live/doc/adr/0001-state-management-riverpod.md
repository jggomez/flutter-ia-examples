# 0001. State management: flutter_riverpod (manual providers, no codegen)

- **Status**: accepted
- **Date**: 2026-09-20
- **Deciders**: flutter-architect

## Context

`rps_live` ("Piedra, Papel o Tijera en vivo") is a small, single-module
Android/iOS app with three screens that all hang off one hard state problem:
a live camera + on-device classifier producing a `Stream<ClassificationResult>`
at ~10-15 fps, which three different consumers need to derive state from:

1. **"Tú vs. IA"**: a countdown/reveal/result state machine (`GamePhase`)
   that samples the classification stream only at reveal time, plus a
   session scoreboard.
2. **"Práctica libre"**: a continuous live view of the same stream, rendered
   as animated per-class confidence meters.
3. **Historial**: an async load of persisted `MatchRecord`s from Hive.

All three need: (a) async/stream-derived state with an explicit
loading/data/error tri-state (the model asset can be missing; the camera can
be unavailable), and (b) a test story that works with **no real device,
emulator, camera, or `.tflite` asset available in CI/dev** — the harness must
inject a fake camera/classifier source and a fake persistence store.

## Decision

Use **`flutter_riverpod` (v3.x)** as the single, app-wide state management
solution, with `Notifier`/`AsyncNotifier` + manual (non-codegen) provider
declarations. `setState` remains allowed for purely ephemeral, local widget
state (e.g. an animation controller), per the skill's rule that local state
is always local regardless of the app-wide choice.

Riverpod's `ProviderContainer(overrides: [...])` / `ProviderScope(overrides:
[...])` is the mechanism used to inject `FakeClassifierRepository` and
`FakeHistoryRepository` in tests (see `lib/ui/providers/repository_providers.dart`),
satisfying the no-camera/no-device testing constraint without any test-only
`if (kDebugMode)` branching in production code.

We use manual provider declarations (`Provider`, `NotifierProvider`,
`AsyncNotifierProvider`) rather than `riverpod_generator`/`@riverpod`
codegen, to keep `build_runner` scoped to the persistence layer
(`hive_generator`) only, and avoid running two independent codegen sources
against the same small codebase. This can be revisited if the app grows
enough providers that manual boilerplate becomes painful (see "Migration
cost" in the skill's decision matrix).

## Alternatives considered

- **`provider` + `ChangeNotifier`** (the pattern in the official
  `flutter-apply-architecture-best-practices` skill) — rejected because it
  has no built-in async tri-state (`AsyncValue`), so the "model missing" /
  "camera unavailable" / "loading" states for the live classifier stream and
  the Hive-backed history load would need hand-rolled flags in every
  ViewModel, and DI overrides for tests rely on `BuildContext`/widget-tree
  lookups rather than a compile-safe container.
- **`flutter_bloc`** — rejected: no team familiarity signal calling for its
  event-sourced traceability, and its ceremony (events, states, mappers) is
  disproportionate to three screens sharing one stream.
- **`signals`** — rejected: good fit for synchronous derived state, weaker
  story for the async loading/error tri-state this app needs in two of its
  three screens (model/camera failure, Hive load failure).
- **Plain `setState` app-wide** — rejected outright: the classifier stream
  must be shared across the vs-AI game logic and the practice-mode meter
  without either owning the camera lifecycle twice; this needs a DI/sharing
  mechanism `setState` doesn't provide.

## Consequences

- Every `ui/features/**` view model composes the same two repository
  abstractions (`ClassifierRepository`, `HistoryRepository`); no screen
  talks to `camera`, `flutter_litert`, or `hive` directly.
- Unit/widget tests can fully cover game logic, preprocessing math, and
  view-model state transitions using `ProviderContainer(overrides: [...])`
  with fakes — no real camera, emulator, or model asset required.
- We take on Riverpod's learning curve/boilerplate relative to `setState`,
  budgeted as acceptable for an app with a genuinely shared async data
  source across three screens.
- If manual provider boilerplate becomes a maintenance burden, migrating to
  `riverpod_generator` is additive (annotate existing classes, keep the same
  public provider names) and does not require a new ADR unless the
  underlying framework changes.

## Addendum (2026-09-20): feature view-model providers must be `.autoDispose`

`flutter-reviewer`'s first pass on the TDD implementation found that
`vsAiViewModelProvider`, `practiceViewModelProvider`, and
`historyViewModelProvider` were declared as plain (non-`autoDispose`)
`NotifierProvider`/`AsyncNotifierProvider`s. Because Riverpod provider
lifecycle is independent of widget mount/unmount unless a provider is
`autoDispose`, this meant:

- Switching between the "Tú vs. IA" and "Práctica libre" tabs never actually
  ran `ref.onDispose` on the outgoing screen's view model, so the shared
  `ClassifierRepositoryImpl` (bound via `overrideWithValue` in `main.dart`)
  had `initialize()` called again on top of its still-live previous state —
  a real leaked `Interpreter`/frame-stream-subscription per tab switch,
  contradicting `app.dart`'s stated "one screen owns the camera at a time"
  design (it used an indexed lookup instead of `IndexedStack` specifically
  to get real unmount semantics, but that alone doesn't dispose a provider).
- `historyViewModelProvider` cached its `AsyncData` for the entire app
  session, so the Historial screen silently went stale after a round was
  played and the user had already visited it once.

**Decision**: `vsAiViewModelProvider`, `practiceViewModelProvider`, and
`historyViewModelProvider` are all declared `.autoDispose`. In the pinned
Riverpod 3.4.3, this is a flag on the provider-declaration builder
(`NotifierProvider.autoDispose<...>(...)` /
`AsyncNotifierProvider.autoDispose<...>(...)`) rather than a separate
`AutoDisposeNotifier`/`AutoDisposeAsyncNotifier` base class (that split was
Riverpod 2.x); the `Notifier`/`AsyncNotifier` subclasses themselves are
unchanged. Combined with `app.dart`'s existing indexed-lookup (real unmount)
navigation, this makes provider
lifecycle match widget lifecycle: leaving a tab disposes its view model
(`ref.onDispose` releases the camera/interpreter), and returning to a tab
re-runs `build()` (Historial gets a fresh Hive read every visit; the
camera-owning screens get a fresh `initialize()`). `classifierRepositoryProvider`
itself stays a plain (non-`autoDispose`) `Provider` — it is stateless
composition-root wiring, not the resource owner; `ClassifierRepositoryImpl`
was made safe for concurrent callers via **reference counting**
(`_activeSessions` in `ClassifierRepositoryImpl`), not the simpler
"unconditionally tear down before creating new" idempotency this addendum
originally called for. That simpler version was tried first and found
unsafe: Riverpod schedules an `.autoDispose` provider's teardown (its lost
listener's `ref.onDispose`) via a microtask *after* the current widget-tree
rebuild, so on a tab switch the incoming screen's `initialize()` runs
*before* the outgoing screen's `dispose()` fires. An unconditional
tear-down-then-rebuild `initialize()` would let that stale, delayed
`dispose()` kill the just-started incoming session moments later.
Reference counting fixes this: `initialize()` while a session is already
live just joins it (no reload); the camera/interpreter are only released
once every caller that initialized has also disposed — safe regardless of
the exact init/dispose interleaving across tab switches. See the
`_activeSessions` doc comment in `classifier_repository_impl.dart` for the
full mechanism, and
`test/regression/classifier_lifecycle_regression_test.dart` for the test
that validates it against the naive alternative.

Rejected alternatives: (a) explicit `ref.invalidate(...)` calls wired from a
`ConsumerStatefulWidget` bottom-nav shell on tab change — works but adds an
imperative lifecycle hook that's easy to forget on the next screen added; (b)
a cross-feature dependency where `VsAiViewModel` invalidates
`historyViewModelProvider` directly after persisting a round — rejected
because it couples the `vs_ai` and `history` features against this ADR's own
"no screen talks to another feature's view model" boundary. `.autoDispose`
achieves the same result declaratively and needs no new inter-feature edges.

Test impact: tests that read an `.autoDispose` provider via
`container.read(...)` across multiple `await`s without an active listener
will see it disposed and rebuilt between reads (state reset). Existing tests
were updated to hold the provider alive for the duration of the test with
`container.listen(provider, (_, __) {}, fireImmediately: true)` where needed
— the standard Riverpod pattern for testing `autoDispose` providers.

## Compliance

`flutter-reviewer` checks:
- No `package:flutter_bloc`, `package:provider`, or `package:signals` import
  anywhere under `lib/` (a second state framework requires a new ADR).
- No `Notifier`/`AsyncNotifier` subclass directly imports `package:camera`,
  `package:flutter_litert`, or `package:hive` — those may only appear under
  `lib/data/**`.
- Every `ui/features/<feature>/view_models/*.dart` file only depends on
  `lib/ui/providers/repository_providers.dart` and/or `lib/domain/**`, never
  on `lib/data/repositories/*_impl.dart` directly.
- New screens live under `lib/ui/features/<feature>/{view_models,views}/`;
  no top-level ad hoc state files outside that structure.
