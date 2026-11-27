"""Unit tests for the A2UI v1.0 catalog, v1.0 examples, app.catalog helpers."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from a2ui.core import A2uiError

from app.catalog import (
    SNAP_SELL_CATALOG_ID,
    get_a2ui_processor,
    renderer_capabilities_from_metadata,
    validate_a2ui_payload,
)

CONTRACTS_DIR = Path(__file__).resolve().parents[3] / "contracts"
CATALOG_PATH = CONTRACTS_DIR / "snap_sell_catalog.json"
EXAMPLES_DIR = CONTRACTS_DIR / "examples" / "1.0"

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


def test_catalog_is_v1_with_custom_components_and_agent_function() -> None:
    raw = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    assert raw["catalogId"] == SNAP_SELL_CATALOG_ID
    assert raw["protocolVersion"] == "1.0"
    assert "instructions" in raw
    assert "theme" not in raw["$defs"]
    assert EXPECTED_CUSTOM_COMPONENTS.issubset(raw["components"])
    assert raw["components"]["StepProgress"]["allowedParents"] == ["Column"]
    assert isinstance(raw["functions"], dict)
    assert "priceFeedback" in raw["functions"]

    catalog = get_a2ui_processor().active_catalogs[0]
    assert catalog.catalog_id == SNAP_SELL_CATALOG_ID
    assert "priceFeedback" in catalog.agent_functions


@pytest.mark.parametrize("example_filename", EXPECTED_EXAMPLES)
def test_all_contract_examples_validate(example_filename: str) -> None:
    payload = json.loads((EXAMPLES_DIR / example_filename).read_text(encoding="utf-8"))
    assert all(message["version"] == "1.0" for message in payload)
    assert "createSurface" in payload[0]
    validate_a2ui_payload(payload)


def test_validate_a2ui_payload_rejects_invalid_component() -> None:
    invalid_payload = [
        {
            "version": "1.0",
            "createSurface": {
                "surfaceId": "selling_step_1_detected",
                "catalogId": SNAP_SELL_CATALOG_ID,
                "components": [{"id": "root", "component": "StepProgress"}],
            },
        }
    ]
    with pytest.raises(A2uiError):
        validate_a2ui_payload(invalid_payload)


def test_renderer_capabilities_from_metadata() -> None:
    sent = {"1.0": {"supportedCatalogIds": [SNAP_SELL_CATALOG_ID]}}
    assert (
        renderer_capabilities_from_metadata({"a2uiRendererCapabilities": sent}) == sent
    )
    assert SNAP_SELL_CATALOG_ID in json.dumps(renderer_capabilities_from_metadata(None))
