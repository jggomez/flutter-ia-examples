# Snap & Sell · Jev — developer guide

Setup, configuration, deployment and internals. For what the app is and how it works, see the [README](../README.md).

## Quickstart

```bash
# 1. Agent (terminal 1)
cd apps/a2ui/snap_sell_jev/agent
cp .env.example .env              # JEV_API_KEY + Gemini
gcloud auth application-default login   # if you use Gemini on Vertex AI
uv sync
uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload

# 2. Flutter app (terminal 2)
cd apps/a2ui/snap_sell_jev/mobile
flutter pub get
flutter run --dart-define-from-file=config/dev.emulator.json   # iOS sim: dev.ios_sim.json
# USB Android phone: adb reverse tcp:8000 tcp:8000, then config/dev.usb.json
```

| Variable (`agent/.env`) | Required | Purpose |
| --- | :---: | --- |
| `JEV_API_KEY` | ✅ | TypeSafe key from [console.typesafe.ai/keys](https://console.typesafe.ai/keys) |
| `GOOGLE_GENAI_USE_ENTERPRISE=true` + `GOOGLE_CLOUD_PROJECT` + `GOOGLE_CLOUD_LOCATION=global` | ✅* | Gemini on Vertex AI (*or* `GEMINI_API_KEY`) |
| `WRITER_MODEL` | | Gemini for data and copy. Default `gemini-3.8-flash`; Cloud Run uses `gemini-3.5-flash-lite` |
| `JEV_MODEL` | | Default `jev-latest` |
| `PUBLIC_BASE_URL` | | URL the phone uses to load uploaded photos (`http://localhost:8000` over USB) |

## Deploy to Cloud Run

```bash
PROJECT=your-project
printf %s "$JEV_API_KEY" | gcloud secrets create jev-api-key --data-file=- --project $PROJECT
gcloud secrets add-iam-policy-binding jev-api-key --project $PROJECT \
  --member=serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
cd agent && gcloud run deploy snap-sell-jev-agent --source . --region us-central1 --project $PROJECT \
  --allow-unauthenticated --cpu-boost --set-secrets=JEV_API_KEY=jev-api-key:latest \
  --set-env-vars=GOOGLE_GENAI_USE_ENTERPRISE=true,GOOGLE_CLOUD_PROJECT=$PROJECT,GOOGLE_CLOUD_LOCATION=global,WRITER_MODEL=gemini-3.5-flash-lite,PUBLIC_BASE_URL=https://SERVICE_URL,APP_URL=https://SERVICE_URL
```

Then point `mobile/config/prod.json` at the service URL. [`agent/cloudbuild.yaml`](../agent/cloudbuild.yaml) does the same from CI. Sessions live in memory, so a restart mid-flow starts over.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `400 Images are experimental` | Jev needs the `TypeSafe-Danger-Zone-Images: true` header. `jev_client.py` sends it. |
| `400 Invalid image dimensions` | Jev accepts roughly 384–1536 px. `jev_client.py` fits every photo to 1024 px. |
| `403 aiplatform.endpoints.predict` | Application Default Credentials belong to another account. Run `gcloud auth application-default login` with an account that has Vertex AI on the project. |
| First photo takes ~15 s on Cloud Run | Cold start after scaling to zero. `--cpu-boost` and starting uvicorn from the venv keep it short; `--min-instances=1` removes it at a cost. |
| "Jev could not decide this step" | `JEV_API_KEY` missing or Jev unreachable. |

## Project layout

```
agent/app/jev_client.py   typesafe-sdk wrapper: image opt-in header, photo resize, timeout
agent/app/decisions.py    the questions for Jev, thresholds, decide_photo / decide_form / decide_details
agent/app/field_bank.py   the form fields, when each is worth asking, and how answers move the price
agent/app/writer.py       Gemini structured output (data and copy only, never UI)
agent/app/surfaces.py     A2UI 1.0 builders, validated against the catalog
agent/app/flow.py         state machine: photo → details → follow-up → preview → published
agent/app/agent.py        ADK BaseAgent; app_utils/a2a.py turns its output into A2A DataParts
mobile/…/jev_decisions_sheet.dart   the "Jev decisions" panel
contracts/examples/jev/   screens built by code, rendered by the Flutter tests
doc/adr/0008              Why Jev
```

## Tests

No network needed: Jev and Gemini are replaced by scripted stand-ins.

```bash
cd agent  && uv run pytest && uv run --extra lint ruff check .   # decisions, forms, flow, ADK runner, A2A SSE
cd mobile && dart analyze && flutter test                         # every code-built screen + decisions panel
```

After changing `surfaces.py` or the field bank: `cd agent && uv run python scripts/export_jev_surfaces.py`.

## Every decision Jev makes

| Step | Jev question | Type | Threshold | Effect on the UI |
| --- | --- | --- | --- | --- |
| Photo | `category` | choice | top option ≥ 40 % | Which screen appears; the probability is the card's confidence |
| Photo | `is_ev` | noul | ≥ 50 % | Battery fields instead of engine displacement |
| Photo | `visible_damage` | noul | ≥ 60 % | Damage box pre-checked, damage question first, notice |
| Photo | `photo_quality` | score 0–3 | < 1.5 | "Retake the photo" hint |
| Photo | `field_<key>` (one per bank field) | noul | ≥ 50 %, top 4 | Which questions the form asks |
| Details | `plausible` | score 0–3 | < 1.0 | Sends the details back once with a warning |
| Details | `condition` | score 0–4 | — | Price ×0.85 (poor) … ×1.06 (like new) |
| Details | `mileage_suspicious` | noul | ≥ 50 % | Asks for an odometer photo |
| Damage photo | `damage_documented` | noul | ≥ 50 % | Accepts the photo or asks for a retake |

Thresholds live in [`decisions.THRESHOLDS`](../agent/app/decisions.py). If Jev is unavailable, the turn fails with "Jev could not decide this step": decisions are never guessed.
