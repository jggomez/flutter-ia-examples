"""A2UI v1.0 catalog, Express inference format and system instructions for Snap & Sell.

What changed from the v0.9 app:

* The catalog is `protocolVersion: "1.0"`. It carries its own `instructions` and
  composition rules (`allowedParents`), so the flow rules below only describe
  the selling stages.
* The model writes **A2UI Express** (`<a2ui>...</a2ui>`) instead of wire JSON
  (`<a2ui-json>`). `ExpressFormatFactory` generates the prompt from the catalog
  schema and compiles each reply into standard v1.0 messages on the server.
* `priceFeedback` is an *agent function*: the renderer calls it with
  `callAgentFunction` and the agent answers without an LLM turn.
"""

from __future__ import annotations

import functools
import json
import os
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from a2ui.core import AgentFunction
from a2ui.core.schema import ProtocolVersion
from a2ui.inference_formats import ExpressFormatFactory
from a2ui.processor import A2uiGenerator, A2uiRequestProcessor, CatalogConfig
from a2ui.utils import read_renderer_capabilities, validate_payload

from app import field_bank
from app.tools import price_feedback


def _patch_express_nested_bindings() -> None:
    """Lets Express accept `$path` values nested inside static object lists.

    a2ui-agent-sdk 0.12.0 decides whether a property may contain bindings by
    walking `items` and `allOf/oneOf/anyOf`, but not an object's `properties`.
    So `DetectedItemCard.fields` (a list of `{key, label, value: DynamicString}`)
    rejects `value: $/detected/brand`, even though the catalog schema allows it
    and the prompt's own example uses it. Every step-1 surface then failed to
    compile and cost two extra model calls. The JSON-schema validation that runs
    after compilation still rejects a whole-list binding such as `fields: $/x`.
    """
    from a2ui.inference_formats.express import compiler

    original = compiler._schema_allows_databinding
    if getattr(original, "_snap_sell_patched", False):
        return

    def allows_databinding(schema: Any) -> bool:
        if original(schema):
            return True
        if not isinstance(schema, dict):
            return False
        children = list((schema.get("properties") or {}).values())
        if isinstance(schema.get("items"), dict):
            children.append(schema["items"])
        for key in ("allOf", "oneOf", "anyOf"):
            children.extend(schema.get(key) or [])
        return any(allows_databinding(child) for child in children)

    allows_databinding._snap_sell_patched = True  # type: ignore[attr-defined]
    compiler._schema_allows_databinding = allows_databinding


_patch_express_nested_bindings()

SNAP_SELL_CATALOG_ID = "https://snap-sell.devhack.dev/a2ui/v1.0/snap_sell_catalog.json"
A2UI_VERSION_KEY = "1.0"

STAGE_SURFACE_IDS: tuple[str, ...] = (
    "selling_step_1_detected",
    "selling_step_2_followup",
    "selling_step_3_preview",
    "selling_step_4_published",
    "selling_unsupported",
)

#: Capabilities assumed when a request does not carry `a2uiRendererCapabilities`
#: (for example the ADK dev UI). The Snap & Sell app always sends them.
DEFAULT_RENDERER_CAPABILITIES: dict[str, Any] = {
    A2UI_VERSION_KEY: {"supportedCatalogIds": [SNAP_SELL_CATALOG_ID]}
}


def resolve_contracts_dir() -> Path:
    """Resolves the directory containing snap_sell_catalog.json across dev and Docker environments."""
    env_override = os.getenv("SNAP_SELL_CONTRACTS_DIR")
    base_dir = Path(__file__).resolve().parent
    candidates = [
        Path(env_override) if env_override else None,
        (base_dir / ".." / ".." / "contracts").resolve(),
        (base_dir / ".." / "contracts").resolve(),
        Path("./contracts").resolve(),
        Path("/code/contracts"),
    ]
    for candidate in candidates:
        if candidate is not None and (candidate / "snap_sell_catalog.json").exists():
            return candidate
    raise FileNotFoundError(
        "Could not locate snap_sell_catalog.json in ../../contracts or ./contracts."
    )


@functools.cache
def get_catalog_config() -> CatalogConfig:
    """Loads the v1.0 catalog and binds the `priceFeedback` agent function handler."""
    base = CatalogConfig.from_path(
        str(resolve_contracts_dir() / "snap_sell_catalog.json"),
        protocol_version=ProtocolVersion.V1_0,
        catalog_id=SNAP_SELL_CATALOG_ID,
    ).catalog
    declared = base.functions["priceFeedback"]
    catalog = base.copy_with(
        agent_functions=[AgentFunction.from_api(declared, price_feedback)]
    )
    return CatalogConfig(catalog=catalog)


@functools.cache
def get_a2ui_generator() -> A2uiGenerator:
    """Agent-level generator: one catalog, v1.0 few-shot examples, Express format."""
    examples_dir = resolve_contracts_dir() / "examples" / "1.0"
    examples = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in sorted(examples_dir.glob("*.json"))
    ]
    return A2uiGenerator(
        [get_catalog_config()],
        examples=examples or None,
        inference_format_factory=ExpressFormatFactory(),
    )


def renderer_capabilities_from_metadata(
    metadata: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """Reads v1.0 `a2uiRendererCapabilities` from transport metadata, with a default."""
    return read_renderer_capabilities(metadata) or DEFAULT_RENDERER_CAPABILITIES


@functools.cache
def get_a2ui_processor() -> A2uiRequestProcessor:
    """Processor negotiated for the Snap & Sell renderer (the only renderer of this agent).

    `create_processor` is the per-request negotiation step: an agent serving
    several renderers would call it with each request's capabilities (see
    `renderer_capabilities_from_metadata`). Snap & Sell has one renderer and a
    static system prompt, so the negotiated processor is cached.
    """
    return get_a2ui_generator().create_processor(DEFAULT_RENDERER_CAPABILITIES)


def validate_a2ui_payload(payload: list[Any] | dict[str, Any]) -> None:
    """Validates A2UI v1.0 wire messages against the Snap & Sell catalog."""
    processor = get_a2ui_processor()
    validate_payload(processor.active_catalogs, payload)  # type: ignore[arg-type]


def build_a2ui_system_instructions() -> str:
    """Builds the system instructions: selling flow rules + the Express prompt snippet."""
    processor = get_a2ui_processor()
    flow_rules = """You are the Snap & Sell AI Marketplace Assistant.
Your role is to inspect user photos of items for sale (cars, motorcycles, smartphones)
and dynamically generate A2UI v1.0 surfaces written in A2UI Express.

### Canonical Stage Surface IDs (Strictly Enforced)
Use ONLY these exact surface ids, one `surface("...")` scope per reply, depending on the stage:
1. `selling_unsupported`: When the uploaded photo is NOT a car, motorcycle, or phone.
   - Render a `Card` with `Icon("warning")`, explanatory `Text`, and a `Button` dispatching `start_new_listing`.
2. `selling_step_1_detected`: After identifying a supported item with `record_detected_item`.
   - Render `StepProgress` (step 1 of 4), `DetectedItemCard`, and a `Card` with a form built FOR THIS PHOTO.
     There is no fixed form per category: two different cars must get different forms.
   - Build the form from the Field Bank below:
     * Always include the `required_missing_fields` returned by `record_detected_item` (after `mileageKm`,
       add a borderless `Button` dispatching `request_odometer_scan`).
     * From its `candidate_fields`, add ONLY those whose `add_when` is true for what you see in the photo,
       at most {max_extra}, most relevant first. Skip anything the photo already answers.
     * If the photo shows damage: put `hasDamage` FIRST, pre-set it to true, and add a short notice `Text`
       above the form saying what damage you see (for example "We can see a dent on the rear door").
       Otherwise put `hasDamage` last.
     * Use the widget, label, options and default listed for each field. Bind each field to `$/details/<key>`
       and initialise every field you show in the data model with its default.
     * The form heading must describe this item (for example "### About your 1987 Mercedes 190E").
   - The contract example below shows ONE possible form; never copy its field list.
   - Include a primary `Button` dispatching `submit_detected_details` whose context includes `category`,
     `brand`, `model`, `year`, `color` (bound to `$/detected/...`) and EVERY field you showed (bound to `$/details/...`).
   - `DetectedItemCard.fields` is STATIC: always write a literal list of maps and bind only each `value`, e.g.
     `[{key: "brand", label: "Brand", value: $/detected/brand, editable: true}, ...]`. Never write `fields` as a `$path`.
3. `selling_step_2_followup`: When `validate_listing_fields` returns `required_followups` (`damage_photo` and/or `odometer_photo`) or when `request_odometer_scan` is triggered.
   - Render `StepProgress` (step 2 of 4), `PhotoRequest` component(s) for each required follow-up photo, a `TextField` for `/followup/damageNotes` when damage was reported, and a primary `Button` dispatching `submit_followup`.
4. `selling_step_3_preview`: When all required fields and follow-ups are complete and `estimate_price_and_build_preview` has been called.
   - Render `StepProgress` (step 3 of 4), `PriceRange` bound to `/pricing/askingPrice`, and `ListingPreview` with `publishAction` (`publish_listing`).
5. `selling_step_4_published`: When the user dispatches `publish_listing`.
   - Render `StepProgress` (step 4 of 4) and a confirmation `Card` with a `Button` dispatching `start_new_listing`.

### Tool Calling Rules
- Call `record_detected_item` first when a new item photo is uploaded.
- Call `validate_listing_fields` when `submit_detected_details` is received.
- Call `extract_odometer_reading` when an odometer photo is uploaded.
- Call `estimate_price_and_build_preview` (pass `user_asking_price=0.0` if not yet set by user) before rendering `selling_step_3_preview`.
- Write the UI as A2UI Express inside `<a2ui>...</a2ui>` tags, as described below. Never write raw A2UI JSON.

### Field Bank (step 1 form)
"""
    flow_rules = flow_rules.replace("{max_extra}", str(field_bank.MAX_EXTRA_FIELDS))
    flow_rules += field_bank.prompt_reference()
    return f"{flow_rules.strip()}\n\n{processor.prompt_snippet.strip()}"
