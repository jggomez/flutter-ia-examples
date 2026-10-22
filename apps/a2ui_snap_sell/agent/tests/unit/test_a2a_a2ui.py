"""Unit tests for A2A/A2UI v0.9 part converters and AgentCard capabilities."""

from __future__ import annotations

import json
from pathlib import Path

from google.adk.a2a import _compat
from google.genai import types as genai_types

from app.app_utils.a2a import (
    A2UI_EXTENSION_URI,
    _default_capabilities,
    convert_snap_sell_a2a_part_to_genai,
    convert_snap_sell_genai_part_to_a2a,
)
from app.catalog import SNAP_SELL_CATALOG_ID

CONTRACTS_DIR = Path(__file__).resolve().parents[3] / "contracts"
CAR_EXAMPLE_PATH = CONTRACTS_DIR / "examples" / "0.9" / "01_detected_car.json"


def test_default_capabilities_advertises_a2ui_v09_extension() -> None:
    """Verifies _default_capabilities includes the A2UI v0.9 extension and catalog IDs."""
    caps = _default_capabilities()
    assert caps.streaming is True
    assert caps.extensions
    a2ui_exts = [e for e in caps.extensions if e.uri == A2UI_EXTENSION_URI]
    assert len(a2ui_exts) == 1
    params_dict = _compat.meta_to_dict(a2ui_exts[0].params) or dict(
        a2ui_exts[0].params or {}
    )
    assert SNAP_SELL_CATALOG_ID in params_dict.get("supportedCatalogIds", [])


def test_convert_a2a_action_datapart_to_genai_text() -> None:
    """Verifies incoming A2UI action DataPart converts to structured GenAI text Part."""
    action_payload = {
        "version": "v0.9",
        "action": {
            "name": "submit_detected_details",
            "surfaceId": "selling_step_1_detected",
            "sourceComponentId": "continue-btn",
            "context": {
                "brand": "Mazda",
                "model": "CX-30",
                "mileageKm": "34200",
            },
        },
    }
    a2a_part = _compat.make_data_part(
        data=action_payload,
        metadata={"mimeType": "application/json+a2ui"},
    )
    converted = convert_snap_sell_a2a_part_to_genai(a2a_part)
    assert isinstance(converted, genai_types.Part)
    assert converted.text is not None
    assert "submit_detected_details" in converted.text
    assert "selling_step_1_detected" in converted.text
    assert "Mazda" in converted.text


def test_convert_a2a_image_filepart_saves_upload_and_appends_url() -> None:
    """Verifies incoming image FilePart is saved to /tmp/snap_sell_uploads and appends URL part."""
    fake_jpeg = (
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
    )
    file_part = _compat.make_file_part_with_bytes(
        data=fake_jpeg,
        mime_type="image/jpeg",
        name="car.jpg",
    )
    converted = convert_snap_sell_a2a_part_to_genai(file_part)
    assert isinstance(converted, list)
    assert len(converted) == 2
    assert converted[0].inline_data is not None
    assert converted[0].inline_data.data == fake_jpeg
    assert converted[1].text is not None
    assert "[Uploaded photo available at image_url:" in converted[1].text
    assert "/uploads/" in converted[1].text


def test_convert_genai_a2ui_text_to_a2a_dataparts() -> None:
    """Verifies <a2ui-json> blocks in GenAI text convert into A2A DataParts with application/json+a2ui."""
    raw_example = CAR_EXAMPLE_PATH.read_text(encoding="utf-8")
    expected_messages = json.loads(raw_example)
    genai_part = genai_types.Part.from_text(
        text=f"I detected a 2021 Mazda CX-30.\n<a2ui-json>\n{raw_example}\n</a2ui-json>"
    )
    a2a_parts = convert_snap_sell_genai_part_to_a2a(genai_part)
    assert isinstance(a2a_parts, list)
    # 1 conversational text part + len(expected_messages) A2UI data parts
    data_parts = [p for p in a2a_parts if _compat.is_data_part(p)]
    text_parts = [p for p in a2a_parts if _compat.is_text_part(p)]
    assert len(text_parts) == 1
    assert "Mazda CX-30" in _compat.part_text(text_parts[0])
    assert len(data_parts) == len(expected_messages)
    for dp in data_parts:
        meta = _compat.part_metadata(dp)
        assert meta.get("mimeType") == "application/json+a2ui"
        data_dict = _compat.data_part_dict(dp)
        assert data_dict.get("version") == "v0.9"
