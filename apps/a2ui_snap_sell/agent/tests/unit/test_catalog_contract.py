"""Unit tests validating snap_sell_catalog.json, v0.9 examples, and app.catalog helpers."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from a2ui.core import A2uiError, A2uiValidationError

from app.catalog import (
    BASIC_CATALOG_ID,
    SNAP_SELL_CATALOG_ID,
    build_a2ui_system_instructions,
    get_a2ui_processor,
    validate_a2ui_payload,
)

CONTRACTS_DIR = Path(__file__).resolve().parents[3] / "contracts"
CATALOG_PATH = CONTRACTS_DIR / "snap_sell_catalog.json"
EXAMPLES_DIR = CONTRACTS_DIR / "examples" / "0.9"

EXPECTED_EXAMPLES = [
    "01_detected_car.json",
    "02_followup_damage_odometer.json",
    "03_detected_phone.json",
    "04_listing_preview.json",
    "05_unsupported_item.json",
]

EXPECTED_CUSTOM_COMPONENTS = {
    "StepProgress",
    "DetectedItemCard",
    "PhotoRequest",
    "PriceRange",
    "ListingPreview",
}


def test_catalog_constants_and_processor() -> None:
    """Verifies catalog IDs and processor initialization."""
    assert (
        SNAP_SELL_CATALOG_ID
        == "https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json"
    )
    assert BASIC_CATALOG_ID == "https://a2ui.org/specification/v0_9/basic_catalog.json"
    assert CATALOG_PATH.exists()

    raw_schema = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    components = set(raw_schema.get("components", {}).keys())
    assert EXPECTED_CUSTOM_COMPONENTS.issubset(components)

    processor = get_a2ui_processor()
    catalog_ids = [c.catalog_id for c in processor.active_catalogs]
    assert SNAP_SELL_CATALOG_ID in catalog_ids
    assert SNAP_SELL_CATALOG_ID in processor.prompt_snippet


def test_build_a2ui_system_instructions_contains_stages_and_examples() -> None:
    """Verifies system instructions include stage surface IDs, rules, and examples."""
    instructions = build_a2ui_system_instructions()
    for stage_id in (
        "selling_step_1_detected",
        "selling_step_2_followup",
        "selling_step_3_preview",
        "selling_step_4_published",
        "selling_unsupported",
    ):
        assert stage_id in instructions
    assert SNAP_SELL_CATALOG_ID in instructions
    assert "DetectedItemCard" in instructions


@pytest.mark.parametrize("example_filename", EXPECTED_EXAMPLES)
def test_all_contract_examples_validate(example_filename: str) -> None:
    """Verifies each 0.9 example validates via validate_a2ui_payload and processor."""
    example_path = EXAMPLES_DIR / example_filename
    assert example_path.exists()

    raw_text = example_path.read_text(encoding="utf-8")
    payload = json.loads(raw_text)
    validate_a2ui_payload(payload)

    processor = get_a2ui_processor()
    wrapped = f"Generated UI:\n<a2ui-json>\n{raw_text}\n</a2ui-json>"
    parts = processor.parse_response(wrapped)
    assert len(parts) >= 2


def test_validate_a2ui_payload_rejects_invalid_component() -> None:
    """Verifies validate_a2ui_payload raises A2uiValidationError on schema violation."""
    invalid_payload = [
        {
            "version": "v0.9",
            "createSurface": {
                "surfaceId": "selling_step_1_detected",
                "catalogId": SNAP_SELL_CATALOG_ID,
            },
        },
        {
            "version": "v0.9",
            "updateComponents": {
                "surfaceId": "selling_step_1_detected",
                "components": [
                    {
                        "id": "root",
                        "component": "StepProgress",
                        # Missing currentStep, totalSteps, stepLabels
                    }
                ],
            },
        },
    ]
    with pytest.raises((A2uiValidationError, A2uiError)):
        validate_a2ui_payload(invalid_payload)
