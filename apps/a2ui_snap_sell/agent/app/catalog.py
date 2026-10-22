"""A2UI v0.9 catalog loader, system instruction builder, and payload validator for Snap & Sell."""

from __future__ import annotations

import functools
import json
import os
from pathlib import Path
from typing import Any

from a2ui.core.basic_catalog import BasicCatalog, ProtocolVersion
from a2ui.processor import A2uiGenerator, A2uiRequestProcessor, CatalogConfig
from a2ui.utils import validate_payload

SNAP_SELL_CATALOG_ID = "https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json"
BASIC_CATALOG_ID = "https://a2ui.org/specification/v0_9/basic_catalog.json"

STAGE_SURFACE_IDS: tuple[str, ...] = (
    "selling_step_1_detected",
    "selling_step_2_followup",
    "selling_step_3_preview",
    "selling_step_4_published",
    "selling_unsupported",
)


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
def get_a2ui_processor() -> A2uiRequestProcessor:
    """Loads snap_sell_catalog.json and v0.9 examples into an A2uiRequestProcessor."""
    contracts_dir = resolve_contracts_dir()
    catalog_path = contracts_dir / "snap_sell_catalog.json"
    examples_dir = contracts_dir / "examples" / "0.9"

    snap_config = CatalogConfig.from_path(
        str(catalog_path),
        protocol_version=ProtocolVersion.V0_9,
    )
    basic_config = CatalogConfig(BasicCatalog(ProtocolVersion.V0_9))

    examples: list[Any] = []
    if examples_dir.exists():
        for ex_path in sorted(examples_dir.glob("*.json")):
            examples.append(json.loads(ex_path.read_text(encoding="utf-8")))

    generator = A2uiGenerator(
        [snap_config, basic_config],
        examples=examples or None,
    )
    return generator.create_processor(
        {
            "v0.9": {
                "supportedCatalogIds": [
                    SNAP_SELL_CATALOG_ID,
                    BASIC_CATALOG_ID,
                ]
            }
        }
    )


def validate_a2ui_payload(payload: list[Any] | dict[str, Any]) -> None:
    """Validates an A2UI v0.9 message or list of messages against the Snap & Sell catalogs."""
    processor = get_a2ui_processor()
    validate_payload(processor.active_catalogs, payload)  # type: ignore[arg-type]


def build_a2ui_system_instructions() -> str:
    """Builds the complete system instructions combining selling flow rules, schema, and examples."""
    processor = get_a2ui_processor()
    flow_rules = f"""You are the Snap & Sell AI Marketplace Assistant.
Your role is to inspect user photos of items for sale (cars, motorcycles, smartphones)
and dynamically generate A2UI v0.9 surfaces using catalogId:
`{SNAP_SELL_CATALOG_ID}`

### Canonical Stage Surface IDs (Strictly Enforced)
Use ONLY these exact `surfaceId` values depending on the selling flow stage:
1. `selling_unsupported`: When the uploaded photo is NOT a car, motorcycle, or phone.
   - Render a `Card` with `Icon("warning")`, explanatory `Text`, and a `Button` dispatching `start_new_listing`.
2. `selling_step_1_detected`: After identifying a supported item with `record_detected_item`.
   - Render `StepProgress` (step 1 of 4), `DetectedItemCard` bound to `/detected/*`, and a `Card` containing ONLY the category-specific questions the photo cannot answer:
     * `car` (ICE): `/details/mileageKm`, optional `request_odometer_scan` button, `/details/engineCc`, `/details/ownersCount`, `/details/papersUpToDate`, `/details/hasDamage`.
     * `car` (EV): `/details/mileageKm`, optional `request_odometer_scan` button, `/details/batteryRangeKm`, `/details/batteryHealthPct`, `/details/ownersCount`, `/details/papersUpToDate`, `/details/hasDamage`.
     * `motorcycle`: `/details/mileageKm`, optional `request_odometer_scan` button, `/details/engineCc`, `/details/ownersCount`, `/details/papersUpToDate`, `/details/hasDamage`.
     * `phone`: `/details/storageGb`, `/details/batteryHealthPct`, `/details/unlocked`, `/details/hasDamage`.
   - Include a primary `Button` dispatching `submit_detected_details`.
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
- Always wrap your A2UI v0.9 JSON message array inside `<a2ui-json>...</a2ui-json>` tags.
"""
    return f"{flow_rules.strip()}\n\n{processor.prompt_snippet.strip()}"
