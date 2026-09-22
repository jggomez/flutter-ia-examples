# Flutter AI

A collection of independent Flutter apps demonstrating on-device and
agentic AI on mobile, plus the notebook used to train one of the models
they use.

Each app under `apps/` is a fully standalone Flutter project (its own
`pubspec.yaml`, no shared package between them). They intentionally share
architectural conventions — a layered `domain` / `data` / `ui` structure,
Riverpod for state, Hive for local persistence, a single dependency
injection composition root, fake-based TDD, and Architecture Decision
Records under each app's `doc/adr/` — so the repo reads as one consistent
system rather than unrelated demos.

## Apps

### `apps/rps_live` — Rock/Paper/Scissors Live

A live-camera hand-gesture classifier turned into a "you vs. the AI" game,
running fully on-device via LiteRT (the current name for the TensorFlow
Lite runtime and file format). See
[`apps/rps_live/README.md`](apps/rps_live/README.md).

Status: built, tested (66 tests), reviewed. Not yet run end-to-end on a
physical device.

### `apps/event_llm_wiki` — Event LLM-Wiki

A conference-agenda wiki with an on-device chat assistant that answers
questions about the agenda using retrieval-augmented generation, fully
offline, citing the specific talks it used. Runs a small Gemma 3 model via
`flutter_litert_lm`. See
[`apps/event_llm_wiki/README.md`](apps/event_llm_wiki/README.md).

Status: architecture and implementation complete (119 tests, clean
analyzer). On-device verification (model download, real inference, full UI
flow on a physical device) is still pending.

### A2UI Planner

Planned but not yet started: an agent-driven itinerary planner built on
Flutter's [GenUI SDK](https://github.com/flutter/genui) and the A2UI
protocol, generating native widgets in response to natural-language
requests rather than only text.

## Notebooks

[`notebooks/`](notebooks/) contains the training notebook for the
Rock/Paper/Scissors model used by `apps/rps_live`, including the two
separate export paths (microcontroller vs. mobile) it produces. See
[`notebooks/README.md`](notebooks/README.md).

## Repository layout

```text
flutter-ai/
├── notebooks/            # model training notebooks
├── apps/
│   ├── rps_live/          # app 1
│   └── event_llm_wiki/    # app 2
├── .agents/skills/        # official Flutter/Dart agent skills
└── .claude/plugins/       # senior-dev-flutter: orchestration/review agents on top of them
```

## Working in this repo

Each app is run and tested independently from its own directory:

```bash
cd apps/rps_live && flutter pub get && flutter test
cd apps/event_llm_wiki && flutter pub get && flutter test
```

See each app's own README for how to run it (including, for
`event_llm_wiki`, the HuggingFace token setup its gated model requires).
