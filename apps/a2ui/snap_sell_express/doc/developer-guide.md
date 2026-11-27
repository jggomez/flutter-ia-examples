# Snap & Sell Express — developer guide

Setup, configuration, deployment and internals. For what the app is and how it works, see the [README](../README.md).

## Quickstart

```bash
# 1. Agent (terminal 1)
cd apps/a2ui/snap_sell_express/agent
cp .env.example .env                     # Gemini via Vertex AI or GEMINI_API_KEY
gcloud auth application-default login    # if you use Vertex AI
uv sync
uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload

# 2. Flutter app (terminal 2)
cd apps/a2ui/snap_sell_express/mobile
flutter pub get
flutter run --dart-define-from-file=config/dev.emulator.json   # iOS sim: dev.ios_sim.json
# USB Android phone: adb reverse tcp:8000 tcp:8000, then config/dev.usb.json
```

| Variable (`agent/.env`) | Purpose |
| --- | --- |
| `GOOGLE_GENAI_USE_ENTERPRISE=true`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION=global` | Gemini on Vertex AI (or set `GEMINI_API_KEY` for AI Studio) |
| `AGENT_MODEL` | Default `gemini-3.8-flash`; Cloud Run uses `gemini-3.5-flash-lite` (~5 s per photo turn) |
| `THINKING_LEVEL` | Default `low`: the agent fills a known template, so deep reasoning only adds latency |
| `PUBLIC_BASE_URL` | URL the phone uses to load uploaded photos (`http://localhost:8000` over USB) |

## Deploy to Cloud Run

```bash
PROJECT=your-project
cd agent && gcloud run deploy snap-sell-express-agent --source . --region us-central1 --project $PROJECT \
  --allow-unauthenticated --cpu-boost \
  --set-env-vars=GOOGLE_GENAI_USE_ENTERPRISE=true,GOOGLE_CLOUD_PROJECT=$PROJECT,GOOGLE_CLOUD_LOCATION=global,AGENT_MODEL=gemini-3.5-flash-lite,PUBLIC_BASE_URL=https://SERVICE_URL,APP_URL=https://SERVICE_URL
```

Then point `mobile/config/prod.json` at the service URL. [`agent/cloudbuild.yaml`](../agent/cloudbuild.yaml) does the same from CI. Sessions live in memory, so a restart mid-flow starts over.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Every photo turn takes 30 s+ | A rejected Express block forces repair calls. `a2ui-agent-sdk` 0.12.0 rejected `$path` values inside `DetectedItemCard.fields`; `catalog.py` patches that check (see its docstring). Also keep `THINKING_LEVEL=low`. |
| `403 aiplatform.endpoints.predict` | Application Default Credentials belong to another account. Run `gcloud auth application-default login` with an account that has Vertex AI on the project. |
| First photo takes ~15 s on Cloud Run | Cold start after scaling to zero. `--cpu-boost` and starting uvicorn from the venv keep it short; `--min-instances=1` removes it at a cost. |
| The phone cannot reach a local agent | Use `adb reverse tcp:8000 tcp:8000` and `config/dev.usb.json`; Android only allows plain HTTP to `localhost`. |

## Project layout

```
agent/app/agent.py        ADK agent: Gemini + tools + Express compile/repair callback
agent/app/catalog.py      Express prompt (flow rules + field bank + catalog), validation
agent/app/field_bank.py   the form fields, when each is worth asking, and how answers move the price
agent/app/tools.py        record item, validate fields, read odometer, price (deterministic)
contracts/                catalog v1.0 + examples; tools/sync_contract.py copies it to agent and mobile
mobile/lib/ui/catalog     Flutter implementations of the custom components
doc/adr/0007              Why 1.0 + Express
```

## Tests

```bash
cd agent  && uv run pytest && uv run --extra lint ruff check .
cd mobile && dart analyze && flutter test
```

After changing the contract: `cd agent && uv run python ../contracts/tools/sync_contract.py`.

## Why A2UI 1.0 + Express (vs v0.9)

| | A2UI v0.9 | 1.0 (this app) |
| --- | --- | --- |
| Gemini writes | Protocol JSON | **Express**, ~50 % smaller prompt for this catalog |
| Messages per screen | `createSurface` + `updateComponents` + `updateDataModel` | One `createSurface` with inline `components` and `dataModel` |
| Bindings | `{"path"}`, `{"call"}` | `{"@path"}`, `{"@call"}`, `@checks` |
| Composition rules | In the prompt | In the catalog (`allowedParents`), enforced on both sides |
| Price feedback | An LLM turn | `callAgentFunction` → deterministic `priceFeedback` |
| Invalid UI | Logged | One automatic repair, otherwise prose only |
