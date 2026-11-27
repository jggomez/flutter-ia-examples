# ADR 0008 — Jev decides, Gemini writes, code assembles the A2UI

- Status: accepted
- Date: 2026-11-21
- Context app: `apps/a2ui/snap_sell_jev`

## Context

In `snap_sell` (v0.9) and `snap_sell_express` (1.0) Gemini writes the UI itself,
as protocol JSON or as A2UI Express. That means a big prompt (catalog + rules +
examples), output that must be validated and sometimes repaired, and screens that
can change between runs for the same input.

[Jev](https://docs.typesafe.ai) (TypeSafe) is a decision model. It does not
generate text. It answers `noul` (yes/no probability), `choice` (option +
probabilities) and `score` (distribution over ordered levels) questions about a
text, JSON or image `state`, all questions in one parallel request.
[jev2ui](https://github.com/dglazkov/jev2ui) shows the pattern for generative UI:
Jev chooses, code builds the tree, an LLM fills only text.

## Decision

The Jev variant keeps the same mobile app, catalog contract and A2A transport,
and replaces the `LlmAgent` with a deterministic ADK `BaseAgent`:

| Role | Who | Where |
|---|---|---|
| Decide (category, EV, damage, photo quality, plausibility, condition, suspicious mileage, damage photo OK) | Jev | `app/decisions.py`, `app/jev_client.py` |
| Write (brand/model/year/color, odometer digits, title, description, rationale) | Gemini with `response_schema` | `app/writer.py` |
| Business rules (validation, km conversion, price band) | code, shared with Express | `app/tools.py` |
| Assemble A2UI v1.0 `createSurface` | code, validated before sending | `app/surfaces.py` |
| Orchestrate one step per turn | state machine | `app/flow.py` |

Code walks Jev's ranking to the first allowed option and applies fixed
thresholds (`decisions.THRESHOLDS`). Jev and Gemini run in parallel for the
photo turn. Each turn sends a decision trace (question, answer, probability,
outcome) as a DataPart with MIME `application/vnd.snap-sell.jev-trace+json`;
renderers ignore it.

If Jev is unavailable (no `JEV_API_KEY`, API error), the turn reports it and
sends no surface: decisions are never guessed. If Gemini fails, the item fields
stay empty for the user to fill, and the listing copy falls back to the
deterministic text from `tools.py`.

## Consequences

- No UI-writing prompt, no Express compile, no repair loop. Every possible
  surface is covered by tests and rendered by the Flutter suite
  (`contracts/examples/jev/`).
- Decisions are explainable (probabilities) and tunable without prompts.
- Less variety: only the screens `surfaces.py` knows how to build.
- One extra paid dependency (TypeSafe key) and a second network hop per turn.
- Question wording and thresholds need a small eval with real photos. None is
  included yet, because no key was available during development.
