# Snap & Sell — Generative UI Marketplace Assistant (A2UI v0.9 + Flutter GenUI + ADK)

A client/server generative UI marketplace assistant where a user snaps or picks a
photo of an item to sell (ICE/EV car, motorcycle, or phone) on a single fixed
entry screen, and a remote Python ADK agent (`gemini-3.8-flash` on Vertex AI /
Cloud Run) dynamically generates every subsequent screen as validated A2UI v0.9
surfaces rendered natively in Flutter via the GenUI SDK.

## Status

Built, TDD-implemented, reviewed, deployed to Cloud Run, and verified end-to-end
on a physical Android device.

- **Python ADK Agent (`agent/`)**: 20/20 `pytest` unit & integration tests
  passing; `agents-cli lint` clean (0 issues). Deployed on Google Cloud Run
  (`us-central1`, `min-instances=0`, `512Mi` RAM, `1 vCPU` throttled).
- **Flutter Mobile Client (`mobile/`)**: 41/41 `flutter test` unit, widget, and
  contract tests passing; `flutter analyze` clean (0 issues).

---

## System Architecture & A2UI Interaction Sequence

![A2UI Interaction Sequence](../../images/a2ui/a2ui-interaction-sequence.png)

1. **Single Fixed Entry Screen (`mobile/`)**: The Flutter app ships only one
   hand-coded screen (`EntryScreen`) where the user captures a photo with the
   camera or selects one from the gallery (resized client-side to max `1280px`
   longest edge, JPEG quality `82`).
2. **In-Band A2A Multimodal Transport**: The mobile client sends the image bytes
   in-band as an A2A `FilePart` (`FileWithBytes`, `image/jpeg`) alongside a
   structured `DataPart` (`clientCapabilities` advertising the custom catalog ID
   `https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`) over
   JSON-RPC + Server-Sent Events (SSE) to `/a2a/app`.
3. **Multimodal Vision & Deterministic ADK Tools (`agent/`)**: The Python ADK
   agent (`gemini-3.8-flash` on Vertex AI) inspects the uploaded photo and
   invokes deterministic tools in [`agent/app/tools.py`](agent/app/tools.py):
   - `record_detected_item`: records the detected category (`car_ice`, `car_ev`,
     `motorcycle`, `phone`, or `unsupported`), brand/model, condition, and
     determines which follow-up questions or photos are required.
   - `validate_listing_fields`: validates user-submitted form fields from the
     A2UI `DataModel` (`/draft/...`) for completeness and plausibility (e.g.,
     year range, mileage bounds, battery health percentage).
   - `extract_odometer_reading`: records mileage extracted via Gemini Vision
     from a follow-up odometer photo and cross-checks it against any manual
     input.
   - `estimate_price_and_build_preview`: computes a deterministic market price
     band (`low`, `recommended`, `high` in USD) and builds the final listing
     preview payload.
4. **Validated A2UI v0.9 Surface Streaming**: The agent wraps generated UI
   definitions in `<a2ui-json>` blocks. An `after_model_callback` validates
   every payload against `contracts/snap_sell_catalog.json` via
   `a2ui-agent-sdk==0.9.0` (`A2uiRequestProcessor`), and the A2A part converter
   in [`agent/app/app_utils/a2a.py`](agent/app/app_utils/a2a.py) emits each
   message (`createSurface`, `updateDataModel`, `updateComponents`) as an A2A
   `DataPart` (`mimeType: application/json+a2ui`).
5. **Native Flutter Rendering & Two-Way Data Binding**: GenUI's
   `SurfaceController` and `Surface` widget render the stage-indexed surfaces
   (`selling_step_1_detected` -> `selling_step_2_followup` ->
   `selling_step_3_preview` -> `selling_step_4_published`) and bind form inputs
   directly to the surface's reactive `DataModel`.

---

## End-to-End Mobile Walkthrough (Physical Android Device)

### Step 1 of 4 — Detected Item (`selling_step_1_detected`)

After snapping or selecting a photo on the entry screen, Gemini Vision identifies
the item and generates a category-specific A2UI v0.9 surface (`DetectedItemCard`
+ pre-filled brand/model/year/color fields + only the missing questions for that
category):

| Step 1 — Detected (Car: 2024 Kia Sonet) | Step 1 — Detected (Motorcycle: 2023 Yamaha Crypton T115) |
| :---: | :---: |
| <img src="../../images/a2ui/01-step1-detected-car.jpeg" alt="Step 1 Detected Car" width="270" /> | <img src="../../images/a2ui/02-step1-detected-motorcycle.jpeg" alt="Step 1 Detected Motorcycle" width="270" /> |
| `CAR` (`95% confidence`): pre-fills Brand, Model, Year, and Color, then adapts the form to car-specific inputs. | `MOTORCYCLE` (`95% confidence`): dynamically adapts the generated A2UI surface to motorcycle-specific attributes. |

### Step 2 of 4 — Follow-Up & Odometer Verification (`selling_step_2_followup`)

When the agent requires visual verification (such as an odometer readout or
close-up damage inspection), it renders a conditional follow-up surface with a
`PhotoRequest` component that captures and uploads the verification photo in-band:

| Step 2 — Follow-Up (`PhotoRequest` for Odometer) |
| :---: |
| <img src="../../images/a2ui/03-step2-odometer-followup.jpeg" alt="Step 2 Odometer Follow-up" width="270" /> |
| Requests a clear dashboard odometer photo (`Take Photo` / `Gallery`) so Gemini Vision can extract and verify mileage via `extract_odometer_reading`. |

### Step 3 of 4 — Price Range & Listing Preview (`selling_step_3_preview`)

Once all fields and follow-up photos are validated, the agent invokes
`estimate_price_and_build_preview` and streams the Step 3 surface combining the
`PriceRange` gauge/slider with the editable `ListingPreview` card and inline
loading state on publish:

| Step 3 — Suggested Price Range (`PriceRange`) | Step 3 — Listing Preview & Publish Spinner (`ListingPreview`) |
| :---: | :---: |
| <img src="../../images/a2ui/04-step3-price-range-preview.jpeg" alt="Step 3 Price Range Preview" width="270" /> | <img src="../../images/a2ui/05-step3-listing-preview-publish.jpeg" alt="Step 3 Listing Preview and Publish Loading State" width="270" /> |
| Displays `Min` / `Recommended` / `Max` USD price band, interactive price slider, asking price input, and pricing rationale. | Shows full specifications (`146,946 km` extracted from odometer), readiness checklist, and the `Publish Listing` button in its active loading state. |

### Step 4 of 4 — Published Confirmation (`selling_step_4_published`)

| Step 4 — Listing Published (`selling_step_4_published`) |
| :---: |
| <img src="../../images/a2ui/06-step4-published.jpeg" alt="Step 4 Published Confirmation" width="270" /> |
| Final agent-generated confirmation surface (`Your 2024 Kia Sonet is now listed for $11,900 USD`) with `Create Another Listing` session reset. |

---

## Architecture & Custom Catalog

```text
a2ui_snap_sell/
├── agent/                  # Python ADK backend (FastAPI + A2A + a2ui-agent-sdk v0.9)
├── mobile/                 # Flutter GenUI client (layered domain / data / ui + Riverpod)
├── contracts/              # Shared A2UI v0.9 JSON Schema catalog & 5 few-shot examples
│   ├── snap_sell_catalog.json
│   ├── CATALOG_CONTRACT.md
│   └── examples/0.9/
├── doc/adr/                # Architecture Decision Records (0001..0006)
└── PLAN.md                 # Engineering execution plan & triage matrix
```

### Shared Custom Catalog (`contracts/snap_sell_catalog.json`)

The catalog (`https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`)
combines 12 standard A2UI v0.9 `BasicCatalog` components with **5 domain-specific
custom components** plus a custom `Button` loading-state override in Flutter:

| Component | Purpose |
| :--- | :--- |
| `StepProgress` | 4-stage horizontal stepper (`Identify` -> `Details` -> `Preview & Price` -> `Publish`) rendered at the top of each surface. |
| `DetectedItemCard` | Hero summary card displaying the detected item title, category badge, confidence pill, and detected attribute chips. |
| `PhotoRequest` | Interactive camera/gallery capture card for conditional follow-up photos (e.g., visible damage or odometer reading) that dispatches `submit_RequestedPhoto`. |
| `PriceRange` | Visual low / recommended / high market price gauge with currency formatting and pricing rationale. |
| `ListingPreview` | Editable final listing card bound to `/draft/title`, `/draft/price`, and `/draft/description` with inline publish spinner and double-tap protection. |
| `Button` (override) | Custom `snapSellButtonItem` override that disables the button and shows an inline `CircularProgressIndicator` while an A2A turn is in flight. |

See [`contracts/CATALOG_CONTRACT.md`](contracts/CATALOG_CONTRACT.md) for the
complete property schemas, `/draft/...` and `/pricing/...` `DataModel` paths, and
`UserActionEvent` contracts.

### Architecture Decision Records (`doc/adr/`)

- [ADR 0001 — Transport, A2A Session Management, and Image Upload Path](doc/adr/0001-transport-a2a-image-upload.md)
- [ADR 0002 — Agent Design, Multi-Step Selling Flow, Tools, Validation, and Surface ID Strategy](doc/adr/0002-agent-design-and-surface-strategy.md)
- [ADR 0003 — Shared Custom Catalog Contract (A2UI v0.9)](doc/adr/0003-custom-catalog-contract.md)
- [ADR 0004 — Flutter State Management, Navigation, and Image Capture](doc/adr/0004-flutter-state-navigation-image-capture.md)
- [ADR 0005 — Cloud Run Deployment, Vertex AI Auth, and Mobile Runtime Configuration](doc/adr/0005-cloud-run-vertex-ai-config.md)
- [ADR 0006 — Folder Layouts and Test Strategy for `agent/` and `mobile/`](doc/adr/0006-folder-layouts-and-test-strategy.md)

---

## Running Locally & Against Cloud Run

### 1. Run the Python ADK Agent Locally

```bash
cd apps/a2ui_snap_sell/agent
agents-cli install
# Ensure .env configures GOOGLE_GENAI_USE_ENTERPRISE=true, GOOGLE_CLOUD_PROJECT, and GOOGLE_CLOUD_LOCATION=global
uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload
```

### 2. Run the Flutter Mobile Client

From `apps/a2ui_snap_sell/mobile/`:

```bash
cd apps/a2ui_snap_sell/mobile
flutter pub get

# Option A: Run against the deployed Cloud Run service (config/prod.json)
flutter run --dart-define-from-file=config/prod.json

# Option B: Run against a local agent on port 8000 (config/local.json)
# If using a physical Android device over USB, forward port 8000 first:
adb reverse tcp:8000 tcp:8000
flutter run --dart-define-from-file=config/local.json
```

Additional environment files in `mobile/config/`:
- `config/dev.emulator.json` (`http://10.0.2.2:8080/a2a/app`)
- `config/dev.ios_sim.json` (`http://127.0.0.1:8080/a2a/app`)
- `config/prod.cloudrun.json` / `config/prod.json` (deployed Cloud Run `/a2a/app` endpoint)

---

## Cloud Run Deployment via Cloud Build

The agent includes a reproducible Cloud Build pipeline
([`agent/cloudbuild.yaml`](agent/cloudbuild.yaml)) and helper script
([`agent/deploy.sh`](agent/deploy.sh)) configured with cost-efficient scaling and
resource bounds (`--memory=512Mi`, `--cpu=1`, `--cpu-throttling`,
`--min-instances=0`, `--max-instances=10`, `--concurrency=10`):

```bash
cd apps/a2ui_snap_sell/agent
./deploy.sh
```

---

## Testing

Both the Python ADK backend and the Flutter client are covered by automated
test suites that run offline without requiring live LLM calls or a physical
camera:

```bash
# Python ADK Agent (20/20 unit & integration tests + Ruff/mypy lint)
cd apps/a2ui_snap_sell/agent
uv run pytest tests/unit tests/integration
agents-cli lint

# Flutter Mobile Client (41/41 unit, widget & contract tests + analyzer)
cd apps/a2ui_snap_sell/mobile
flutter analyze
flutter test
```
