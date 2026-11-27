# 0002. Agent Design, Multi-Step Selling Flow, Tools, Validation, and Surface ID Strategy

- **Status**: accepted
- **Date**: 2026-10-21
- **Deciders**: flutter-architect

## Context

After receiving the user's item photo, the Python ADK agent must:
1. Identify the item (`car`, `motorcycle`, `phone`, or `unsupported`) and render a pre-filled editable detection card plus only the category-specific questions the photo cannot answer (including EV-specific battery/range fields when an electric car/motorcycle is detected).
2. React to user answers with conditional follow-up surfaces (e.g., if `hasDamage == true`, request a damage photo via `PhotoRequest`; if the user opts to scan the odometer or leaves mileage blank on a car/motorcycle, request an odometer photo via `PhotoRequest`, read the mileage with Gemini Vision, and pre-fill it) and reject implausible field values (e.g., negative mileage, year `1850`, phone storage `999 GB`, battery health `150%`).
3. Generate a final listing preview (`ListingPreview` + `PriceRange`) with a suggested price range, generated title/description, missing-items checklist, and a mock Publish action.

We also must align with the actual `a2ui-agent-sdk == 0.9.0` + `a2ui-a2a == 0.1.0` APIs rather than the deprecated `0.7.x` `A2uiSchemaManager` shown in older docs.

## Decision

1. **Single ADK `Agent` (`root_agent` + `app`) Following `/google-agents-cli-adk-code` Best Practices**:
   - Preserve the `agents-cli` scaffold conventions in `app/agent.py`:
     - `MODEL = "gemini-3.8-flash"`
     - `root_agent = Agent(name="snap_sell_agent", model=Gemini(model=MODEL, retry_options=types.HttpRetryOptions(attempts=3)), instruction=..., tools=[...], before_agent_callback=..., after_model_callback=...)`
     - `app = App(root_agent=root_agent, name="app")`
   - Define deterministic Python function tools in `app/tools.py` strictly adhering to ADK tool rules (mandatory type hints, **zero default parameter values**, clear docstrings that do not mention `tool_context`, `tool_context: ToolContext` as final parameter, and JSON-serializable `dict` returns):
     - `record_detected_item(category: str, brand: str, model: str, year_or_generation: str, color: str, condition_summary: str, confidence: float, is_ev: bool, visible_damage: bool, image_url: str, tool_context: ToolContext) -> dict`: Validates category (`car` | `motorcycle` | `phone` | `unsupported`), initializes `tool_context.state["listing_draft"]`, and returns required category/powertrain question fields (`car` ICE, `car` EV, `motorcycle`, or `phone`).
     - `validate_listing_fields(fields_json: str, tool_context: ToolContext) -> dict`: Enforces deterministic domain validation bounds (plausible year `1970..current_year+1`, mileage `0..600_000` km, engine `49..8_000` cc, battery health `1..100`%, phone storage in `{32, 64, 128, 256, 512, 1024, 2048}` GB, price `> 0`), merges valid fields into `tool_context.state["listing_draft"]`, and returns `{"status": ..., "valid": bool, "field_errors": dict, "required_followups": list}`.
     - `extract_odometer_reading(raw_reading_text: str, unit: str, tool_context: ToolContext) -> dict`: Parses and normalizes odometer digits extracted by Gemini Vision from a follow-up odometer photo (`unit` is `"km"` or `"mi"`), validates plausibility, and updates `mileageKm` in `tool_context.state["listing_draft"]`.
     - `estimate_price_and_build_preview(user_asking_price: float, currency: str, tool_context: ToolContext) -> dict`: Computes a deterministic heuristic price band (`minPrice`, `suggestedPrice`, `maxPrice`, `rationale`), `generatedTitle`, `generatedDescription`, `specs`, and `missingChecklist`.
2. **A2UI Schema Generation, Callback Validation, and Part Conversion (`a2ui-agent-sdk == 0.9.0`)**:
   - Load `../contracts/snap_sell_catalog.json` via `CatalogConfig.from_path(catalog_path, protocol_version=ProtocolVersion.V0_9)` into `A2uiGenerator([catalog_config])` and `A2uiRequestProcessor`.
   - Inject `processor.prompt_snippet` plus validated few-shot examples from `../contracts/examples/0.9/*.json` into `root_agent`'s instruction.
   - Use `before_agent_callback` to initialize `state["listing_draft"]` and `state["stage"]`, and `after_model_callback` to validate `<a2ui-json>` blocks via `processor.parse_response(...)`.
   - Convert `<a2ui-json>` blocks into A2A `DataPart`s (`mimeType: application/json+a2ui`) in `app/app_utils/a2a.py`'s `gen_ai_part_converter`.
3. **Surface ID Strategy — One Stable Surface ID per Flow Stage**:
   - Use canonical stage surface IDs:
     - `selling_unsupported`: When the uploaded photo is not a car, motorcycle, or phone.
     - `selling_step_1_detected`: Initial detection (`StepProgress` step 1 + `DetectedItemCard` + category-specific missing questions + optional "Scan odometer photo" button).
     - `selling_step_2_followup`: Conditional follow-up surface (`StepProgress` step 2 + `PhotoRequest` for damage and/or odometer photo, or validation correction form when implausible values are submitted).
     - `selling_step_3_preview`: Final listing review (`StepProgress` step 3 + `PriceRange` + `ListingPreview`).
     - `selling_step_4_published`: Mock published confirmation surface (`StepProgress` step 4 + summary card + `start_new_listing` button).
   - When the agent advances to a new stage, it emits `createSurface` + `updateComponents` + `updateDataModel` for the new stage's `surfaceId`. When re-rendering the *same* stage (e.g., showing inline validation errors or pre-filling mileage after an odometer photo), it emits `updateComponents` + `updateDataModel` on the existing `surfaceId`.

## Alternatives considered

- **Multi-agent sub-agent graph (separate DetectorAgent, ValidatorAgent, PricerAgent, UiRendererAgent)** — rejected because each turn would require multiple sequential LLM round-trips (adding 3–6 seconds of latency per tap on mobile), whereas a single `Agent` calling deterministic Python tools completes in one tool-call loop.
- **Single surface ID (`main_surface`) overwritten on every step** — rejected because overwriting a single surface destroys previous step trees in `SurfaceController`, preventing the user from navigating back to inspect or edit earlier steps on mobile.
- **Pure LLM validation and pricing without Python tools** — rejected because LLMs inconsistently enforce numeric bounds and price math; deterministic Python tools make validation and price bands 100% unit-testable with `pytest`.

## Consequences

- **Positive**: Fast single-agent turns, deterministic tool-backed validation and pricing, full compatibility with `agents-cli run`, `agents-cli playground`, `agents-cli eval`, and `agents-cli deploy`.
- **Positive**: Stage-based surface IDs allow the Flutter client to maintain a back-navigable history stack of surfaces while still supporting in-place updates for validation errors or OCR pre-fills.

## Compliance

Track A reviewer checks:
- `app/agent.py` preserves `MODEL = "gemini-3.8-flash"`, `root_agent`, and `app = App(root_agent=root_agent, name="app")`.
- All tools in `app/tools.py` have type hints, zero default values on parameters, docstrings that do not mention `tool_context`, and dict return types.
- All 4 tools (`record_detected_item`, `validate_listing_fields`, `extract_odometer_reading`, `estimate_price_and_build_preview`), catalog validation, and A2A/A2UI part converters have pure-Python unit tests in `tests/unit/` requiring zero network or Vertex AI calls, while agent behavioral tests live in `tests/eval/`.
