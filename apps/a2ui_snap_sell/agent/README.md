# snap-sell-agent — Python ADK & A2UI v0.9 Backend (`agent/`)

The remote Python ADK backend for **Snap & Sell**, scaffolded with
`google-agents-cli` (`1.11.0`) and powered by `gemini-3.8-flash` on Vertex AI,
`a2a-sdk`, and `a2ui-agent-sdk==0.9.0`.

This agent receives item photos and user form actions over the A2A protocol
(`/a2a/app`), inspects images with multimodal vision, invokes deterministic
validation and pricing tools, and streams back schema-validated A2UI v0.9
surfaces (`createSurface`, `updateDataModel`, `updateComponents`).

For the full end-to-end architecture, mobile client overview, and ADRs, see the
parent [`../README.md`](../README.md).

---

## Project Structure

```text
agent/
├── app/
│   ├── agent.py               # Root ADK Agent (`gemini-3.8-flash`), callbacks & A2UI system prompt
│   ├── catalog.py             # A2uiGenerator + A2uiRequestProcessor (loads snap_sell_catalog.json)
│   ├── tools.py               # 4 deterministic ADK tools for item detection, validation & pricing
│   ├── fast_api_app.py        # FastAPI server exposing /a2a/app & Agent Card endpoints
│   └── app_utils/
│       ├── a2a.py             # A2A routes, A2UI v0.9 extension & FilePart/DataPart converters
│       └── services.py        # Session & artifact service configuration
├── contracts/                 # Copy of shared snap_sell_catalog.json & 0.9 few-shot examples
├── tests/
│   ├── unit/                  # Deterministic unit tests for tools, catalog validation & A2A converters
│   ├── integration/           # FastAPI & A2A endpoint integration tests
│   └── eval/                  # ADK evaluation datasets & config
├── cloudbuild.yaml            # Cloud Build pipeline for Cloud Run deployment
├── deploy.sh                  # Helper script to trigger Cloud Build deployment
├── Dockerfile                 # Production container image definition
└── pyproject.toml             # Project dependencies managed with uv
```

---

## Key Components

### 1. A2UI v0.9 Extension & Part Converters (`app/app_utils/a2a.py`)

- **Agent Card Extension**: Advertises the A2UI v0.9 extension URI
  `https://a2ui.org/a2a-extension/a2ui/v0.9` in `_default_capabilities()` so
  `genui_a2a` clients automatically negotiate A2UI v0.9 surface streaming.
- **Inbound A2A -> GenAI Part Converter (`convert_a2a_part_to_genai_part`)**:
  - Converts incoming A2A `FilePart` (`FileWithBytes`, `image/jpeg` or
    `image/png`) into `google.genai.types.Part(inline_data=Blob(...))` so
    `gemini-3.8-flash` directly sees item, damage, and odometer photos.
  - Converts incoming A2UI `DataPart` user actions (`{"action": {"name": ..., "surfaceId": ..., "context": ...}}`)
    into structured text prompts for the ADK runner while ignoring metadata-only
    `a2uiClientCapabilities` payloads.
- **Outbound GenAI -> A2A Part Converter (`convert_genai_part_to_a2a_part`)**:
  - Splits model output around `<a2ui-json>...</a2ui-json>` delimiters via
    `A2uiRequestProcessor.split_Parts`, parses each validated A2UI v0.9 JSON
    message, and wraps it in an A2A `DataPart` with
    `metadata={"mimeType": "application/json+a2ui"}`.

### 2. Deterministic ADK Tools (`app/tools.py`)

All tools follow ADK tool conventions (strict type annotations, no default
parameter values, JSON-serializable `dict` returns, and session state persistence
via `tool_context: ToolContext`):

1. `record_detected_item`: Records the visually identified category (`car_ice`,
   `car_ev`, `motorcycle`, `phone`, or `unsupported`), brand/model, condition,
   and visible attributes, and returns required category-specific fields plus
   whether a follow-up photo (`damage` or `odometer`) is needed.
2. `validate_listing_fields`: Validates user-submitted form fields from the
   surface `DataModel` (`/draft/...`) for required keys and domain plausibility
   (e.g., manufacturing year bounds, mileage range, EV battery health `1..100%`).
3. `extract_odometer_reading`: Records the odometer reading extracted from a
   follow-up dashboard photo and flags discrepancies (`>15%`) against manually
   entered mileage.
4. `estimate_price_and_build_preview`: Calculates a deterministic market price
   band (`low`, `recommended`, `high` in USD) with human-readable rationale and
   prepares the final listing preview state.

### 3. Catalog Validation (`app/catalog.py` & `app/agent.py`)

- Loads `contracts/snap_sell_catalog.json` (`https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`)
  and the 5 few-shot examples under `contracts/examples/0.9/` using
  `a2ui-agent-sdk==0.9.0`.
- `after_model_callback` validates every `<a2ui-json>` block emitted by the LLM
  against the catalog JSON Schema before it reaches the client.

---

## Requirements

- **uv**: Python package manager — [Install](https://docs.astral.sh/uv/getting-started/installation/)
- **agents-cli**: Google Agents CLI (`uv tool install google-agents-cli`)
- **Google Cloud SDK**: `gcloud` CLI authenticated against GCP project `devhack-3f0c2`

---

## Quick Start (Local Development)

1. Install dependencies:
   ```bash
   cd apps/a2ui_snap_sell/agent
   agents-cli install
   ```
2. Configure `.env` (see `.env.example`):
   ```dotenv
   GOOGLE_GENAI_USE_ENTERPRISE=true
   GOOGLE_CLOUD_PROJECT=devhack-3f0c2
   GOOGLE_CLOUD_LOCATION=global
   ```
3. Run the FastAPI + A2A server locally on port 8000:
   ```bash
   uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload
   ```
   Or launch the interactive ADK playground:
   ```bash
   agents-cli playground
   ```

---

## Testing & Linting

```bash
cd apps/a2ui_snap_sell/agent
uv run pytest tests/unit tests/integration
agents-cli lint
```

- **20 automated tests** (`tests/unit/` and `tests/integration/`) verify all 4
  ADK tools, catalog JSON Schema validation on all 5 few-shot examples,
  `after_model_callback` sanitization, and A2A `FilePart` / `DataPart`
  round-trip conversion.
- **`agents-cli lint`** runs `ruff` and `mypy` with zero warnings or errors.

---

## Cloud Run Deployment via Cloud Build

Production deployment uses [`cloudbuild.yaml`](cloudbuild.yaml) and
[`deploy.sh`](deploy.sh) to build the container image in Artifact Registry and
deploy to Cloud Run (`us-central1`) with cost-safe scaling and resource limits:

- **Memory**: `512Mi`
- **CPU**: `1 vCPU` with `--cpu-throttling` enabled (billed only during active requests)
- **Scaling**: `--min-instances=0`, `--max-instances=10`, `--concurrency=10`

```bash
cd apps/a2ui_snap_sell/agent
./deploy.sh
```

---

## Commands Reference

| Command | Description |
| :--- | :--- |
| `agents-cli install` | Install dependencies using `uv` |
| `uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload` | Run local A2A FastAPI server on port 8000 |
| `agents-cli playground` | Launch local interactive ADK web playground |
| `uv run pytest tests/unit tests/integration` | Run the 20 unit and integration tests |
| `agents-cli lint` | Run code quality and static type checks (`ruff` + `mypy`) |
| `./deploy.sh` | Build and deploy to Cloud Run via Cloud Build (`cloudbuild.yaml`) |
