# 0004. Persistence: Hive for chat history (derived from rps_live ADR 0002)

- **Status**: accepted
- **Date**: 2026-09-22
- **Deciders**: flutter-architect

## Context

`event_llm_wiki` must persist the single-thread chat conversation
(`ChatMessage`: id, role, text, timestamp, citations) across app restarts,
so relaunching the app shows the previous conversation instead of an empty
thread. The schema is a single flat, append-only entity with no relations
between messages, no complex filtered/sorted queries — "all messages,
oldest first" covers every requirement. There is also no real
device/emulator available in CI/dev for the automated suite (the connected
Android device is reserved for manual on-device
checkpoints — see PLAN.md — not for `flutter test`), so whatever store is
chosen must be exercisable in a plain `flutter test` process with no
platform channel round-trip.

This is the same shape `apps/rps_live`'s ADR 0002 already decided for match
history — see
[`apps/rps_live/doc/adr/0002-persistence-hive.md`](../../../rps_live/doc/adr/0002-persistence-hive.md)
for the full original rationale (why Hive over sqflite/shared_preferences/
in-memory-only). This ADR does not re-litigate that choice; it records why
`event_llm_wiki` inherits it and the two decisions specific to this app's
persisted shape.

## Decision

Use **Hive** (`hive` + `hive_flutter`, with `hive_generator` +
`build_runner` as dev dependencies — same versions as rps_live) for chat
history persistence, behind the `ChatHistoryRepository` interface
(`domain/repositories/chat_history_repository.dart`). The domain layer
never imports `package:hive`; only
`data/repositories/chat_history_repository_impl.dart` and
`data/models/chat_message_dto.dart` do. `data/local/hive_boxes.dart` is the
single source of truth for the box name (`chat_history`) and `typeId`
registry (`ChatMessageDto` = 0) — mirroring rps_live's
`data/local/hive_boxes.dart` convention exactly.

### Model-download progress is NOT persisted

Unlike chat history, model-download state has **no Hive DTO at all** and no
persisted flag anywhere (not Hive, not `shared_preferences`, nothing). Local
file existence — checked live by
`ModelDownloadRepositoryImpl.checkLocalStatus()` via `AppStorageService` —
is always the single source of truth for whether the model is ready (see
`doc/adr/0005-model-download-flow.md`). This is a deliberate simplicity
choice: a persisted "isDownloaded" flag would need to be kept in sync with
the filesystem by hand (what happens if the flag says `true` but the user
cleared app storage, or a previous download was killed mid-write?), and
re-deriving the truth from the filesystem on every app launch is cheap
(one `stat` call) and trivially self-healing — there is no state to go
stale.

### `ChatMessageDto` stores only `citedTalkIds`, not full `Talk` objects

`ChatMessageDto` (`data/models/chat_message_dto.dart`) persists a message's
citations as `List<String> citedTalkIds` — talk ids only. It does NOT
duplicate `Talk` title/abstract/speaker/time content into the chat-history
box. `assets/agenda.json` already bundles that content once; persisting it
again per cited message would create a second, independently-stale copy of
agenda data with no benefit (the agenda is bundled and read-only — there is
no "the agenda changed since this message was sent" scenario to protect
against by snapshotting it). `ChatHistoryRepositoryImpl.getAll()` re-joins
`citedTalkIds` against `AgendaRepository.getTalkById` (via
`ChatMessageDto.toDomain`'s `resolveCitation` callback) to rebuild the full
`Citation` list, including `Citation.talkTitle`, on every load. A citation
id that no longer resolves (an edge case, since the bundled agenda does not
change at runtime) is dropped rather than surfaced as an error — see that
method's doc comment.

## Alternatives considered

Not re-litigated for the Hive-vs-sqflite-vs-shared_preferences question
itself — see rps_live's ADR 0002. Specific to this app:

- **Persisting a "model downloaded" boolean flag (Hive or
  `shared_preferences`)** — rejected: adds a second source of truth that
  can drift from the actual filesystem state (see "Model-download progress
  is NOT persisted" above) for no benefit over a cheap `stat` check.
- **Persisting full `Talk` snapshots inside `ChatMessageDto`** — rejected:
  duplicates bundled, read-only agenda content for no benefit (see above),
  and would require a migration path if `Talk`'s shape ever changes,
  independent of chat history's own schema evolution.

## Consequences

- Adding a new `ChatMessage` field means adding a `@HiveField` to
  `ChatMessageDto` and bumping `data/local/hive_boxes.dart`'s registry
  comment trail if a new `@HiveType` is ever introduced — same discipline
  as rps_live's ADR 0002.
- `ChatHistoryRepositoryImpl` depends on both a `Box<ChatMessageDto>` and
  `AgendaRepository` (for citation re-joining) — the only
  `data/repositories/*_impl.dart` in this app with two collaborators beyond
  its own DTO/box.
- `ChatHistoryRepositoryImpl` is fully unit-testable via an in-memory Hive
  box (`Hive.init(tempDir)`) plus a `FakeAgendaRepository`; PLAN.md phase 6
  calls this out as a "real tempdir Hive box" test (not a fake at the Hive
  level) — matching rps_live's `HistoryRepositoryImpl` test approach.
- `typeId` collisions silently corrupt data; any new `@HiveType` in this
  app must be registered in `data/local/hive_boxes.dart` first.

## Compliance

`flutter-reviewer` checks:
- No `package:sqflite`, `package:sqflite_common_ffi`, or
  `package:shared_preferences` import anywhere under `lib/` without a new
  ADR superseding this one.
- `package:hive`/`package:hive_flutter` imports only appear under
  `lib/data/**` (never `lib/domain/**` or `lib/ui/**`).
- `ChatMessageDto` never gains a field that duplicates `Talk` content
  (title/abstract/speakers/day/track/startTime) — citations stay id-only.
- No Hive box, `shared_preferences` key, or other persisted flag is ever
  introduced to track model-download status — `checkLocalStatus()` must
  stay filesystem-derived.
- Every new persisted field goes through `ChatMessageDto` +
  `lib/data/local/hive_boxes.dart`'s `typeId`/box registry, never a
  standalone `Hive.openBox` call scattered elsewhere.
