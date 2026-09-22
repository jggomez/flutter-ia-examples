# 0002. Persistence: Hive for match history

- **Status**: accepted
- **Date**: 2026-09-20
- **Deciders**: flutter-architect

## Context

`rps_live` must persist match history (`MatchRecord`: id, timestamp, player
move, AI move, outcome) across app restarts, plus let the Historial screen
show derived aggregate stats (win/lose/tie counts). The schema is a single
flat, append-mostly entity with no relations to any other entity, no joins,
and no complex filtered/sorted SQL queries — "all records, most recent
first" plus in-memory aggregation covers every current requirement. There is
also **no real device/emulator available in CI/dev**, so whatever store is
chosen must be exercisable in a plain `flutter test` / `dart test` process
without a platform channel round-trip.

## Decision

Use **Hive** (`hive` + `hive_flutter`, with `hive_generator` +
`build_runner` as dev dependencies) for match history persistence, behind
the `HistoryRepository` interface (`lib/domain/repositories/history_repository.dart`).
The domain layer never imports `package:hive`; only
`lib/data/repositories/history_repository_impl.dart` and
`lib/data/models/match_record_dto.dart` do.

## Alternatives considered

- **sqflite** — rejected: it is a relational engine for a single flat,
  unindexed, relation-free entity — no query in this app's scope needs SQL
  joins, filtering, or migrations beyond "add a field". sqflite also talks
  to the platform's native SQLite via a method channel, which typically
  requires `sqflite_common_ffi` (desktop/VM) shims to unit-test without a
  real device/emulator; Hive's core package has no platform-channel
  dependency for reads/writes (only `hive_flutter`'s `initFlutter()`
  convenience helper touches `path_provider`), so tests can `Hive.init()`
  against a temp directory in a plain VM test with no ffi shim.
- **`shared_preferences`** — rejected: intended for small scalar
  key-value settings, not a growing list of structured records; would
  require manually (de)serializing a JSON list on every write, discarding
  Hive's per-key access as history grows.
- **In-memory only (no persistence)** — rejected outright: the requirement
  explicitly states history must survive app restart.

## Consequences

- Adding a new `MatchRecord` field means adding a `@HiveField` to
  `MatchRecordDto` and bumping a schema version field if a non-additive
  change is ever needed (Hive has no formal migration system beyond
  "handle missing/default fields defensively" or "open a new box and
  migrate manually" — acceptable given the tiny, flat schema).
- `hive_generator`/`build_runner` is now a dev dependency solely for this
  layer; it must not creep into providing codegen for state management
  (see ADR 0001, which deliberately avoids `riverpod_generator` to keep
  `build_runner` scoped here).
- `HistoryRepositoryImpl` is fully unit-testable via an in-memory Hive box
  (`Hive.init(tempDir)`), and `flutter-implementer`'s game-logic/view-model
  tests never need Hive at all — they depend on `HistoryRepository`, faked.
- `typeId` collisions silently corrupt data; `lib/data/local/hive_boxes.dart`
  is the single source of truth for registered `typeId`s and box names —
  any new `@HiveType` must be registered there first.

## Compliance

`flutter-reviewer` checks:
- No `package:sqflite`, `package:sqflite_common_ffi`, or
  `package:shared_preferences` import anywhere under `lib/` without a new
  ADR superseding this one.
- `package:hive`/`package:hive_flutter` imports only appear under
  `lib/data/**` (never `lib/domain/**` or `lib/ui/**`).
- Every new persisted field goes through `MatchRecordDto` +
  `lib/data/local/hive_boxes.dart`'s `typeId`/box registry, never a
  standalone `Hive.openBox` call scattered elsewhere.
