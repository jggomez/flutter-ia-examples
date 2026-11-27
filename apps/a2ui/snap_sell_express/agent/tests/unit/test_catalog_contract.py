"""Unit tests for the A2UI v1.0 catalog, v1.0 examples, Express compilation and app.catalog helpers."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from a2ui.core import A2uiError
from a2ui.parser import A2uiPart, TextPart, to_message_dicts

from app.catalog import (
    SNAP_SELL_CATALOG_ID,
    STAGE_SURFACE_IDS,
    build_a2ui_system_instructions,
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

UNSUPPORTED_EXPRESS = """Sorry, that item is not supported yet.
<a2ui>
surface("selling_unsupported")
$/msg = "Only cars, motorcycles and phones."
root = Card(col)
col = Column([warn, txt, btn])
warn = Icon("warning")
txt = Text($/msg)
btn = Button(lbl, "primary", Event("start_new_listing", {}))
lbl = Text("Try another photo")
</a2ui>"""


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


def test_system_instructions_use_express_and_list_stages() -> None:
    instructions = build_a2ui_system_instructions()
    for stage_id in STAGE_SURFACE_IDS:
        assert stage_id in instructions
    assert "<a2ui>" in instructions
    assert "<a2ui-json>" not in instructions
    assert "PriceRange(" in instructions  # Express signature derived from the catalog


def test_express_prompt_is_smaller_than_direct_json() -> None:
    from a2ui.inference_formats import DirectJsonFormatFactory

    from app.catalog import DEFAULT_RENDERER_CAPABILITIES, get_a2ui_generator

    express = get_a2ui_processor().prompt_snippet
    direct_json = (
        get_a2ui_generator()
        .create_processor(
            DEFAULT_RENDERER_CAPABILITIES,
            inference_format_factory=DirectJsonFormatFactory(),
        )
        .prompt_snippet
    )
    assert len(express) < len(direct_json) * 0.7


@pytest.mark.parametrize("example_filename", EXPECTED_EXAMPLES)
def test_all_contract_examples_validate(example_filename: str) -> None:
    payload = json.loads((EXAMPLES_DIR / example_filename).read_text(encoding="utf-8"))
    assert all(message["version"] == "1.0" for message in payload)
    assert "createSurface" in payload[0]
    validate_a2ui_payload(payload)


def test_express_block_compiles_to_single_v1_create_surface() -> None:
    parts = get_a2ui_processor().parse_response(UNSUPPORTED_EXPRESS, wrapped=True)
    assert isinstance(parts[0], TextPart)
    a2ui_parts = [p for p in parts if isinstance(p, A2uiPart)]
    assert len(a2ui_parts) == 1
    messages = to_message_dicts(a2ui_parts[0].a2ui)
    assert len(messages) == 1
    create = messages[0]["createSurface"]
    assert messages[0]["version"] == "1.0"
    assert create["surfaceId"] == "selling_unsupported"
    assert create["catalogId"] == SNAP_SELL_CATALOG_ID
    assert create["dataModel"] == {"msg": "Only cars, motorcycles and phones."}
    text = next(c for c in create["components"] if c["id"] == "txt")
    assert text["text"] == {"@path": "/msg"}


def test_express_block_breaking_allowed_parents_is_rejected() -> None:
    bad = """<a2ui>
surface("selling_step_3_preview")
root = Card(sp)
sp = StepProgress(3, 4, ["Photo", "Details", "Price", "Publish"])
</a2ui>"""
    with pytest.raises(A2uiError, match="Allowed parents"):
        get_a2ui_processor().parse_response(bad, wrapped=True)


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


_DETECTED_CARD_BLOCK = """<a2ui>
surface("selling_step_1_detected")
root = Card(col)
col = Column([detected_card])
detected_card = DetectedItemCard("car", $/detected/imageUrl, 0.94, $/detected/summary, false, FIELDS)
</a2ui>"""


def test_detected_item_card_accepts_path_values_inside_static_fields() -> None:
    # Regression: a2ui-agent-sdk 0.12.0 rejected the prompt's own example, which
    # forced a repair model call (~14 s) on every step-1 surface.
    fields = '[{key: "brand", label: "Brand", value: $/detected/brand, editable: true}]'
    get_a2ui_processor().parse_response(
        _DETECTED_CARD_BLOCK.replace("FIELDS", fields), wrapped=True
    )


def test_detected_item_card_still_rejects_binding_the_whole_fields_list() -> None:
    with pytest.raises(A2uiError):
        get_a2ui_processor().parse_response(
            _DETECTED_CARD_BLOCK.replace("FIELDS", "$/detected/fields"), wrapped=True
        )


def test_prompt_builds_the_form_from_the_field_bank_not_fixed_lists() -> None:
    from app import field_bank

    prompt = build_a2ui_system_instructions()
    assert "### Field Bank" in prompt
    for spec in field_bank.FIELD_BANK:
        assert f"`{spec.key}`" in prompt
    # the old per-category fixed forms are gone
    assert "`car` (ICE):" not in prompt
    assert f"at most {field_bank.MAX_EXTRA_FIELDS}" in prompt
