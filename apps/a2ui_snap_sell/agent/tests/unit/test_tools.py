"""Pure Python unit tests for Snap & Sell ADK tools."""

from __future__ import annotations

import inspect
import json
from dataclasses import dataclass, field
from typing import Any

from app.tools import (
    estimate_price_and_build_preview,
    extract_odometer_reading,
    record_detected_item,
    validate_listing_fields,
)


@dataclass
class _StubToolContext:
    """Stub ToolContext with an in-memory state dict for pure unit tests."""

    state: dict[str, Any] = field(default_factory=dict)


def test_adk_tool_signatures_follow_strict_rules() -> None:
    """Verifies all 4 tools have type hints, zero default values, and clean docstrings."""
    tools = [
        record_detected_item,
        validate_listing_fields,
        extract_odometer_reading,
        estimate_price_and_build_preview,
    ]
    for fn in tools:
        sig = inspect.signature(fn)
        assert fn.__doc__, f"{fn.__name__} must have a docstring"
        assert "tool_context" not in fn.__doc__, (
            f"{fn.__name__} docstring must not mention tool_context"
        )
        for param_name, param in sig.parameters.items():
            assert param.annotation is not inspect.Parameter.empty, (
                f"{fn.__name__} parameter {param_name} is missing a type hint"
            )
            assert param.default is inspect.Parameter.empty, (
                f"{fn.__name__} parameter {param_name} must not have a default value"
            )


def test_record_detected_item_car_ice_and_ev() -> None:
    """Verifies record_detected_item for ICE and EV cars."""
    ctx = _StubToolContext()
    res_ice = record_detected_item(
        category="car",
        brand="Mazda",
        model="CX-30",
        year_or_generation="2021",
        color="Soul Red",
        condition_summary="Clean SUV exterior",
        confidence=0.94,
        is_ev=False,
        visible_damage=False,
        image_url="http://localhost:8000/uploads/car.jpg",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_ice["status"] == "success"
    assert res_ice["category"] == "car"
    assert "engineCc" in res_ice["required_missing_fields"]
    assert res_ice["recommended_surface_id"] == "selling_step_1_detected"
    assert ctx.state["listing_draft"]["brand"] == "Mazda"
    assert (
        ctx.state["listing_draft"]["imageUrl"]
        == "http://localhost:8000/uploads/car.jpg"
    )

    ctx_ev = _StubToolContext()
    res_ev = record_detected_item(
        category="car",
        brand="Tesla",
        model="Model 3",
        year_or_generation="2023",
        color="White",
        condition_summary="Electric sedan",
        confidence=0.96,
        is_ev=True,
        visible_damage=True,
        image_url="http://localhost:8000/uploads/ev.jpg",
        tool_context=ctx_ev,  # type: ignore[arg-type]
    )
    assert res_ev["status"] == "success"
    assert res_ev["is_ev"] is True
    assert "batteryRangeKm" in res_ev["required_missing_fields"]
    assert "batteryHealthPct" in res_ev["required_missing_fields"]


def test_record_detected_item_phone_motorcycle_and_unsupported() -> None:
    """Verifies record_detected_item for motorcycle, phone, and unsupported items."""
    ctx_moto = _StubToolContext()
    res_moto = record_detected_item(
        category="motorcycle",
        brand="Yamaha",
        model="MT-07",
        year_or_generation="2022",
        color="Cyan Storm",
        condition_summary="Clean naked bike",
        confidence=0.93,
        is_ev=False,
        visible_damage=False,
        image_url="http://localhost:8000/uploads/moto.jpg",
        tool_context=ctx_moto,  # type: ignore[arg-type]
    )
    assert res_moto["status"] == "success"
    assert res_moto["category"] == "motorcycle"
    assert "mileageKm" in res_moto["required_missing_fields"]
    assert "engineCc" in res_moto["required_missing_fields"]
    assert res_moto["recommended_surface_id"] == "selling_step_1_detected"

    ctx_phone = _StubToolContext()
    res_phone = record_detected_item(
        category="phone",
        brand="Apple",
        model="iPhone 15 Pro",
        year_or_generation="2023",
        color="Natural Titanium",
        condition_summary="Minor wear",
        confidence=0.95,
        is_ev=False,
        visible_damage=False,
        image_url="http://localhost:8000/uploads/phone.jpg",
        tool_context=ctx_phone,  # type: ignore[arg-type]
    )
    assert res_phone["status"] == "success"
    assert res_phone["category"] == "phone"
    assert "storageGb" in res_phone["required_missing_fields"]

    ctx_unsup = _StubToolContext()
    res_unsup = record_detected_item(
        category="unsupported",
        brand="Unknown",
        model="Toaster",
        year_or_generation="2020",
        color="Silver",
        condition_summary="Kitchen toaster",
        confidence=0.91,
        is_ev=False,
        visible_damage=False,
        image_url="http://localhost:8000/uploads/toaster.jpg",
        tool_context=ctx_unsup,  # type: ignore[arg-type]
    )
    assert res_unsup["status"] == "success"
    assert res_unsup["category"] == "unsupported"
    assert res_unsup["recommended_surface_id"] == "selling_unsupported"


def test_validate_listing_fields_bounds_and_followups() -> None:
    """Verifies validate_listing_fields enforces bounds and detects follow-ups."""
    ctx = _StubToolContext(
        state={
            "listing_draft": {
                "category": "car",
                "brand": "Mazda",
                "model": "CX-30",
                "year": "2021",
            }
        }
    )

    invalid_json = json.dumps(
        {
            "year": 1850,
            "mileageKm": -50,
            "engineCc": 99999,
            "batteryHealthPct": 150,
            "storageGb": 999,
            "askingPrice": -10,
        }
    )
    res_bad = validate_listing_fields(
        fields_json=invalid_json,
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_bad["status"] == "error"
    assert res_bad["valid"] is False
    for key in (
        "year",
        "mileageKm",
        "engineCc",
        "batteryHealthPct",
        "storageGb",
        "askingPrice",
    ):
        assert key in res_bad["field_errors"]

    valid_with_followup = json.dumps(
        {
            "year": 2021,
            "mileageKm": "",
            "engineCc": 2000,
            "hasDamage": True,
        }
    )
    res_followup = validate_listing_fields(
        fields_json=valid_with_followup,
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_followup["status"] == "success"
    assert res_followup["valid"] is True
    assert "odometer_photo" in res_followup["required_followups"]
    assert "damage_photo" in res_followup["required_followups"]
    assert res_followup["recommended_surface_id"] == "selling_step_2_followup"


def test_extract_odometer_reading_km_and_miles() -> None:
    """Verifies extract_odometer_reading normalizes km and converts miles."""
    ctx = _StubToolContext(state={"listing_draft": {"category": "car"}})
    res_km = extract_odometer_reading(
        raw_reading_text="034,200 km",
        unit="km",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_km["status"] == "success"
    assert res_km["mileageKm"] == 34200
    assert ctx.state["listing_draft"]["mileageKm"] == 34200

    res_mi = extract_odometer_reading(
        raw_reading_text="10,000",
        unit="mi",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_mi["status"] == "success"
    assert 16090 <= res_mi["mileageKm"] <= 16100

    res_err = extract_odometer_reading(
        raw_reading_text="950,000",
        unit="km",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_err["status"] == "error"

    res_neg = extract_odometer_reading(
        raw_reading_text="-1200 km",
        unit="km",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res_neg["status"] == "error"


def test_estimate_price_and_build_preview() -> None:
    """Verifies estimate_price_and_build_preview computes band and preview fields."""
    ctx = _StubToolContext(
        state={
            "listing_draft": {
                "category": "car",
                "brand": "Mazda",
                "model": "CX-30",
                "year": "2021",
                "color": "Soul Red",
                "mileageKm": 34200,
                "engineCc": 2000,
                "ownersCount": ["1"],
                "papersUpToDate": True,
                "hasDamage": False,
                "imageUrl": "http://localhost:8000/uploads/car.jpg",
            }
        }
    )
    res = estimate_price_and_build_preview(
        user_asking_price=0.0,
        currency="USD",
        tool_context=ctx,  # type: ignore[arg-type]
    )
    assert res["status"] == "success"
    assert res["minPrice"] < res["suggestedPrice"] < res["maxPrice"]
    assert res["askingPrice"] == res["suggestedPrice"]
    assert "Mazda" in res["generatedTitle"]
    assert res["generatedDescription"]
    assert len(res["specs"]) >= 3
    assert len(res["missingChecklist"]) >= 2
    assert "price_estimate" in ctx.state

    ctx_moto = _StubToolContext(
        state={
            "listing_draft": {
                "category": "motorcycle",
                "brand": "Yamaha",
                "model": "MT-07",
                "year": "2022",
                "color": "Cyan Storm",
                "mileageKm": 12000,
                "engineCc": 689,
                "ownersCount": ["1"],
                "papersUpToDate": True,
                "hasDamage": True,
                "damagePhotoUrl": "http://localhost:8000/uploads/dmg.jpg",
                "imageUrl": "http://localhost:8000/uploads/moto.jpg",
            }
        }
    )
    res_moto = estimate_price_and_build_preview(
        user_asking_price=6500.0,
        currency="USD",
        tool_context=ctx_moto,  # type: ignore[arg-type]
    )
    assert res_moto["status"] == "success"
    assert res_moto["category"] == "motorcycle"
    assert res_moto["askingPrice"] == 6500
    assert "Yamaha" in res_moto["generatedTitle"]
