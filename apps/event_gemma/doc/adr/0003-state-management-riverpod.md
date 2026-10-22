# 0003. State management: flutter_riverpod (derived from rps_live ADR 0001)

- **Status**: accepted
- **Date**: 2026-09-22
- **Deciders**: flutter-architect

## Context

This app is the second app in a multi-app repo whose first app,
`apps/rps_live`, already established `flutter_riverpod` (manual providers,
no codegen) as this repo's state management convention — see
[`apps/rps_live/doc/adr/0001-state-management-riverpod.md`](../../../rps_live/doc/adr/0001-state-management-riverpod.md)
and its addendum for the full original rationale (async tri-state via
`AsyncValue`, `ProviderContainer(overrides: [...])` as the test-injection
seam, why `provider`/`ChangeNotifier`, `flutter_bloc`, `signals`, and
app-wide `setState` were all rejected). This ADR does not re-litigate that
choice; it records **why `event_llm_wiki` inherits it** and the one
deliberate, documented exception this app's shape requires.

`event_llm_wiki` has the same underlying shape rps_live's ADR was written
for: multiple screens (Agenda list/detail, model setup, chat) needing an
explicit loading/data/error tri-state around async, sometimes-failing I/O
(`assets/agenda.json` parsing, a streamed model download, on-device
inference), with a hard requirement that `flutter test` never touch the
real asset bundle, real network, real filesystem, or the real
`flutter_litert_lm` engine (see PLAN.md's testing constraint).

## Decision

Use **`flutter_riverpod` (v3.x)**, manual (non-codegen)
`Notifier`/`AsyncNotifier` provider declarations — the same convention as
`apps/rps_live`, for the same reasons recorded in that app's ADR 0001. As
there, `setState` remains allowed for purely ephemeral, local widget state
(e.g. `_HomeTabs`'s `_selectedIndex` in `app.dart`).

`ui/providers/repository_providers.dart` is this app's composition root —
four `Provider`s (`agendaRepositoryProvider`, `chatEngineRepositoryProvider`,
`chatHistoryRepositoryProvider`, `modelDownloadRepositoryProvider`), each
`throw UnimplementedError()` until overridden in `main.dart` (real
implementations) or in a test's `ProviderContainer(overrides: [...])` (fakes)
— identical shape to rps_live's two-provider composition root.

### Provider `.autoDispose` defaults, and the one documented exception

Following rps_live's addendum (feature view-model providers are
`.autoDispose` so provider lifecycle matches widget mount/unmount),
`agendaListViewModelProvider`, `talkDetailViewModelProvider` (`.family`),
and `modelDownloadViewModelProvider` are all `.autoDispose`.

**`chatViewModelProvider` is deliberately NOT `.autoDispose`** — the one
documented exception to this repo's default pattern. rps_live's
`ClassifierRepositoryImpl` needed reference counting
(`_activeSessions`, see that app's ADR 0001 addendum) because its
`ClassifierRepository` was shared across **two** `.autoDispose` screens
(`vs_ai` and `practice`) racing `initialize()`/`dispose()` against each
other on tab switch — Riverpod schedules an `.autoDispose` provider's
teardown via a microtask *after* the current rebuild, so the incoming
screen's `initialize()` could run before the outgoing screen's stale
`dispose()` fires and tear down the just-started session.

`event_llm_wiki` has exactly **one** consumer of `ChatEngineRepository`:
`ChatViewModel`. There is no second screen, no tab-switch race, and no
reason to ever reload the ~529 MB model mid-session — once the Chat tab has
paid the model-load cost once, it should stay loaded for the rest of the
app session, including if the user switches to the Agenda tab and back.
Making `chatViewModelProvider` a plain (non-`.autoDispose`)
`AsyncNotifierProvider` achieves exactly that: the provider (and the engine
it initializes) lives for the `ProviderScope`'s lifetime, not the widget's.
Because there is only ever one caller, `ChatEngineRepositoryImpl` only needs
a **simple idempotent-init boolean guard** (`initialize()` is a no-op if
already initialized; `dispose()` is a no-op if not), not rps_live's
reference counting — there is no concurrent-caller race to make reference
counting necessary. See
`data/repositories/chat_engine_repository_impl.dart`'s doc comment for the
full argument, and PLAN.md phase 9 for the regression test that pins this
(`ChatEngineRepository`'s fake `create()` must run at most once across a
tab-away/tab-back cycle).

## Alternatives considered

Not re-litigated here — see rps_live's ADR 0001 for `provider`/
`ChangeNotifier`, `flutter_bloc`, `signals`, and app-wide `setState`, all
rejected there for reasons that apply equally to this app's shape. The one
alternative specific to this app:

- **Reference-counting `ChatEngineRepositoryImpl` "to be safe" even with
  only one consumer** — rejected: reference counting exists specifically to
  resolve a *concurrent-caller* race that does not exist here (one
  consumer, one non-`.autoDispose` provider). Adding it anyway would be
  unnecessary complexity mirroring a different app's problem this app
  doesn't have — see that class's doc comment for the explicit instruction
  not to "upgrade" to reference counting without a new consumer actually
  appearing.

## Consequences

- Every `ui/features/**` view model composes the four repository
  abstractions under `ui/providers/repository_providers.dart` (or a use
  case built on top of them); no screen talks to `package:flutter_litert_lm`,
  `package:hive`, `package:http`, or `package:path_provider` directly.
- `ChatViewModel`'s state (and the loaded engine) survives Agenda<->Chat tab
  switches; a fresh `AsyncNotifier.build()` only happens once per app
  session (or on an explicit `ref.invalidate` this app's scope does not
  currently call anywhere — see PLAN.md's non-goals: no "reset
  conversation" action).
- If a second consumer of `ChatEngineRepository` is ever added, this ADR's
  exception needs to be revisited (likely converging back toward rps_live's
  reference-counting pattern) — that is a new architectural decision, not a
  silent code change.

## Compliance

`flutter-reviewer` checks:
- No `package:flutter_bloc`, `package:provider`, or `package:signals`
  import anywhere under `lib/` (a second state framework requires a new
  ADR).
- No `Notifier`/`AsyncNotifier` subclass directly imports
  `package:flutter_litert_lm`, `package:hive`, `package:http`, or
  `package:path_provider` — those may only appear under `lib/data/**`.
- Every `ui/features/<feature>/view_models/*.dart` file only depends on
  `lib/ui/providers/repository_providers.dart` and/or `lib/domain/**`,
  never on `lib/data/repositories/*_impl.dart` directly.
- `chatViewModelProvider` is the ONLY non-`.autoDispose` feature
  view-model provider in this app; any new non-`.autoDispose` provider
  requires an ADR update explaining why (same bar this exception was held
  to).
- New screens live under `lib/ui/features/<feature>/{view_models,views}/`;
  no top-level ad hoc state files outside that structure.
