# 0002. RAG retrieval: plain-Dart weighted lexical scoring, no embeddings

- **Status**: accepted
- **Date**: 2026-09-22
- **Deciders**: flutter-architect

## Context

The Chat tab must ground its answers in `assets/agenda.json`'s ~20 talks
(see that file for the actual bundled content: 2 days x 2 tracks, ~5 talks
per day/track combination) so the on-device model (ADR 0001) answers from
the real agenda instead of hallucinating. The corpus is small (tens of
records, not thousands), fully bundled and read-only (no in-app agenda
editing/sync — see PLAN.md's non-goals), and structured (title, speakers,
abstract, day, track, time) rather than free-form prose. The whole retrieval
step must also run fully offline, with no separate embedding model, index
build step, or native dependency beyond what ADR 0001 already introduces.

## Decision

Use a **plain-Dart lexical/keyword field-weighted scorer** —
`RetrieveRelevantTalksUseCase` — over the in-memory `List<Talk>` `Agenda
Repository` already caches. No embeddings, no vector index, no external
search engine.

Algorithm (see `retrieve_relevant_talks_use_case.dart`'s doc comment for the
authoritative version `flutter-implementer` TDDs against):

1. Normalize the query: lowercase, strip punctuation, split on whitespace,
   drop stopwords.
2. For each `Talk`, compute a weighted exact-token-membership score:
   title tokens x3, speaker-name tokens x2, track/day label tokens x1,
   abstract tokens x1.
3. Drop talks scoring zero.
4. Sort by score desc, then title-match-count desc, then `startTime` asc,
   then `id` asc (full deterministic tie-break — see `RetrievedTalk`'s doc
   comment for why each tie-break field exists).
5. Return the top 3.

A query matching nothing returns an empty list — never an exception, never
a fallback to unrelated talks. `BuildChatPromptUseCase` is responsible for
turning that empty result into an explicit "no matching talk found in this
agenda" instruction to the model, so the model states that honestly instead
of inventing an answer (see PLAN.md's phase 12 acceptance check on this
exact behavior).

Citations shown in the UI (`CitationChip`s under an assistant reply) are
always this use case's output (`RetrievedTalk` → `Citation`), computed
**before** generation — never parsed back out of the model's free-text
response. This makes citations exact and deterministic regardless of
anything the model says, and means a citation can never point at a talk the
model didn't actually see in its prompt.

## Alternatives considered

- **Embeddings-based RAG** (an on-device embedding model + a vector
  index/similarity search) — rejected: for a few dozen short, structured
  records, a second on-device model just to compute embeddings is
  disproportionate engineering and runtime cost (extra model download,
  extra load time, extra memory) for retrieval quality gains that mostly
  matter at a much larger corpus size or for genuinely fuzzy/semantic
  querying prose search doesn't already handle well as structured-field
  matching. Revisit if the agenda's real-world content ever grows to
  hundreds/thousands of talks or the corpus stops being clean structured
  fields (e.g. long transcripts).
- **sqlite/FTS5** — rejected for the same reason ADR 0002 in `rps_live`
  rejected `sqflite` for its persistence layer: this is a small, read-only,
  fully-in-memory-representable corpus with no relational structure to
  exploit and no need for FTS5's ranking sophistication (BM25, etc.) over a
  simple, fully-understood, hand-tunable weighted scorer that is trivial to
  exhaustively unit test with synthetic fixtures (see PLAN.md phase 2).
  Bringing in a native SQLite dependency purely for full-text search on 20
  short JSON records is not worth the added surface area.
- **Sending the entire agenda in every prompt (no retrieval step at all)**
  — rejected: even at ~20 talks, the full agenda's title+abstract+speaker
  text risks crowding out useful context-window budget against Gemma3-1B-IT's
  4096-token limit once system instructions and multi-turn history are
  added (see PLAN.md phase 9's multi-turn note), and retrieval also gives
  precise, minimal citations instead of "the model could have used any of
  20 talks."

## Consequences

- `RetrieveRelevantTalksUseCase` and `BuildChatPromptUseCase` are pure Dart,
  zero Flutter/plugin imports, and are the highest-value, fastest tests to
  write first (PLAN.md phase 2) since `ChatViewModel` and the on-device
  checkpoints both depend on them being correct.
- Retrieval quality is bounded by exact-token matching — synonyms,
  misspellings, and paraphrases the query doesn't share vocabulary with the
  agenda's own text will not match. This is an accepted, documented
  limitation given the corpus size and offline-only constraint, not an
  oversight.
- Because citations are computed before generation, a change to the scoring
  weights/algorithm can change which citations appear for a given query
  without needing any change to `BuildChatPromptUseCase` or
  `ChatEngineRepository` — the two are decoupled by `RetrievedTalk` as a
  stable interface between them.

## Compliance

`flutter-reviewer` checks:
- No `package:sqflite`, no vector/embedding package, and no network-backed
  search dependency anywhere under `lib/` without a new ADR superseding
  this one.
- `RetrieveRelevantTalksUseCase` and `BuildChatPromptUseCase` have zero
  imports from `dart:io`, `package:flutter/*`, or any plugin package — pure
  Dart only.
- `ChatViewModel`/`ChatScreen` never construct `Citation`s from parsing the
  streamed model text — citations must trace back to a
  `RetrieveRelevantTalksUseCase` call's output.
