# Snap & Sell · Jev — Python ADK Agent

A deterministic ADK agent (`SnapSellJevAgent`, a custom `BaseAgent`). No LLM writes UI:

- **Jev** (`typesafe-sdk`) answers the decision questions in `app/decisions.py`, about the photo or the form data.
- **Gemini** (`google-genai`, `response_schema`) writes item attributes, odometer digits and listing copy (`app/writer.py`).
- **Code** applies thresholds, runs the business rules (`app/tools.py`) and assembles A2UI v1.0 surfaces (`app/surfaces.py`). `app/flow.py` orchestrates one step per turn.

The A2A server, photo uploads and the `priceFeedback` agent function are the same as in `snap_sell_express`.

See the [Snap & Sell · Jev README](../README.md) and [ADR 0008](../doc/adr/0008-jev-decision-model.md).

## Run

```bash
cp .env.example .env    # JEV_API_KEY + Gemini config
uv sync
uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000
```

## Test

```bash
uv run pytest                              # no network: fake Jev and fake writer
uv run --extra lint ruff check .
uv run python scripts/export_jev_surfaces.py   # refresh contracts/examples/jev for the Flutter tests
```
