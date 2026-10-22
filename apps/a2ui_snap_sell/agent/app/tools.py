"""Deterministic ADK tools for item detection, field validation, odometer extraction, and pricing."""

from __future__ import annotations

import json
import re
from datetime import UTC, datetime
from typing import Any

from google.adk.tools import ToolContext

ALLOWED_PHONE_STORAGE_GB: frozenset[int] = frozenset(
    {32, 64, 128, 256, 512, 1024, 2048}
)
MILES_TO_KM_FACTOR = 1.60934
USD_TO_COP_RATE = 4100

PREMIUM_BRANDS: frozenset[str] = frozenset(
    {
        "apple",
        "audi",
        "bmw",
        "ducati",
        "lexus",
        "mercedes",
        "mercedes-benz",
        "porsche",
        "tesla",
        "triumph",
    }
)
MID_HIGH_BRANDS: frozenset[str] = frozenset(
    {
        "google",
        "honda",
        "kawasaki",
        "mazda",
        "samsung",
        "subaru",
        "toyota",
        "volkswagen",
        "yamaha",
    }
)


def _normalize_category(raw: str) -> str:
    cleaned = (raw or "").strip().lower()
    if cleaned in ("car", "auto", "automobile", "suv", "sedan", "truck", "vehicle"):
        return "car"
    if cleaned in ("motorcycle", "moto", "motorbike", "scooter", "bike"):
        return "motorcycle"
    if cleaned in ("phone", "smartphone", "cellphone", "mobile", "iphone", "android"):
        return "phone"
    return "unsupported"


def _required_missing_fields(category: str, is_ev: bool) -> list[str]:
    if category == "unsupported":
        return []
    if category in ("car", "motorcycle"):
        if is_ev:
            return [
                "mileageKm",
                "batteryRangeKm",
                "batteryHealthPct",
                "ownersCount",
                "papersUpToDate",
                "hasDamage",
            ]
        return [
            "mileageKm",
            "engineCc",
            "ownersCount",
            "papersUpToDate",
            "hasDamage",
        ]
    return [
        "storageGb",
        "batteryHealthPct",
        "unlocked",
        "hasDamage",
    ]


def _parse_int(value: Any) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return round(value)
    text = str(value).strip().replace(",", "")
    if not text:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def _extract_scalar(value: Any) -> Any:
    if isinstance(value, list):
        return value[0] if value else None
    return value


def record_detected_item(
    category: str,
    brand: str,
    model: str,
    year_or_generation: str,
    color: str,
    condition_summary: str,
    confidence: float,
    is_ev: bool,
    visible_damage: bool,
    image_url: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Records the visually detected item from the uploaded photo and returns required category questions.

    Call this tool immediately after inspecting the user's initial item photo.

    Args:
        category: Detected item category ('car', 'motorcycle', 'phone', or 'unsupported').
        brand: Detected brand or manufacturer (for example 'Mazda', 'Apple', 'Yamaha').
        model: Detected model name (for example 'CX-30', 'iPhone 15 Pro', 'MT-07').
        year_or_generation: Estimated model year or generation string (for example '2021').
        color: Detected exterior color or finish.
        condition_summary: Short visual summary of the detected item's appearance.
        confidence: Vision detection confidence score between 0.0 and 1.0.
        is_ev: True if the vehicle is battery-electric (EV), False otherwise.
        visible_damage: True if dents, cracks, or scratches are visible in the photo.
        image_url: URL of the uploaded item photo.

    Returns:
        Dictionary with status, normalized detection fields, required_missing_fields, and recommended_surface_id.
    """
    norm_category = _normalize_category(category)
    ev_flag = bool(is_ev) if norm_category in ("car", "motorcycle") else False
    missing_fields = _required_missing_fields(norm_category, ev_flag)
    recommended_surface_id = (
        "selling_unsupported"
        if norm_category == "unsupported"
        else "selling_step_1_detected"
    )
    clamped_confidence = round(max(0.0, min(1.0, float(confidence))), 2)
    resolved_image_url = (
        image_url.strip() or "http://10.0.2.2:8000/uploads/demo_item.jpg"
    )
    summary_text = (
        condition_summary.strip()
        or f"{year_or_generation} {brand} {model} ({color})".strip()
    )

    draft: dict[str, Any] = {
        "category": norm_category,
        "brand": brand.strip(),
        "model": model.strip(),
        "year": year_or_generation.strip(),
        "color": color.strip(),
        "summary": summary_text,
        "confidence": clamped_confidence,
        "isEv": ev_flag,
        "hasDamage": bool(visible_damage),
        "imageUrl": resolved_image_url,
    }

    existing_draft = dict(tool_context.state.get("listing_draft", {}))
    existing_draft.update(draft)
    tool_context.state["listing_draft"] = existing_draft
    tool_context.state["stage"] = recommended_surface_id

    return {
        "status": "success",
        "category": norm_category,
        "brand": draft["brand"],
        "model": draft["model"],
        "year_or_generation": draft["year"],
        "color": draft["color"],
        "condition_summary": summary_text,
        "confidence": clamped_confidence,
        "is_ev": ev_flag,
        "visible_damage": bool(visible_damage),
        "image_url": resolved_image_url,
        "required_missing_fields": missing_fields,
        "recommended_surface_id": recommended_surface_id,
    }


def validate_listing_fields(
    fields_json: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Validates user-submitted listing fields for plausibility and determines follow-up requirements.

    Call this tool when the user submits category details from the detection form.

    Args:
        fields_json: JSON object string containing the submitted form fields (for example year, mileageKm, engineCc, batteryHealthPct, storageGb, askingPrice, hasDamage).

    Returns:
        Dictionary with status ('success' or 'error'), valid boolean, field_errors dict, required_followups list, and recommended_surface_id.
    """
    try:
        parsed_fields = json.loads(fields_json) if fields_json.strip() else {}
        if not isinstance(parsed_fields, dict):
            return {
                "status": "error",
                "valid": False,
                "field_errors": {"_form": "fields_json must decode to a JSON object."},
                "required_followups": [],
                "recommended_surface_id": "selling_step_1_detected",
            }
    except json.JSONDecodeError as exc:
        return {
            "status": "error",
            "valid": False,
            "field_errors": {"_form": f"Invalid JSON payload: {exc}"},
            "required_followups": [],
            "recommended_surface_id": "selling_step_1_detected",
        }

    draft: dict[str, Any] = dict(tool_context.state.get("listing_draft", {}))
    merged: dict[str, Any] = {**draft, **parsed_fields}
    category = _normalize_category(str(merged.get("category", "car")))
    field_errors: dict[str, str] = {}

    max_year = max(datetime.now(UTC).year, 2026) + 1
    raw_year = merged.get("year")
    if raw_year is not None and str(raw_year).strip() != "":
        year_val = _parse_int(raw_year)
        if year_val is None or not (1970 <= year_val <= max_year):
            field_errors["year"] = f"Year must be between 1970 and {max_year}."

    raw_mileage = merged.get("mileageKm", merged.get("mileage_km"))
    mileage_missing = False
    if category in ("car", "motorcycle"):
        if (
            raw_mileage is None
            or str(raw_mileage).strip() == ""
            or str(raw_mileage).strip().lower() in ("unknown", "uncertain", "scan")
        ):
            mileage_missing = True
        else:
            mileage_val = _parse_int(raw_mileage)
            if mileage_val is None or not (0 <= mileage_val <= 600_000):
                field_errors["mileageKm"] = "Mileage must be between 0 and 600,000 km."

    raw_cc = merged.get("engineCc", merged.get("engine_cc"))
    if raw_cc is not None and str(raw_cc).strip() != "":
        cc_val = _parse_int(raw_cc)
        if cc_val is None or not (49 <= cc_val <= 8_000):
            field_errors["engineCc"] = (
                "Engine displacement must be between 49 and 8,000 cc."
            )

    raw_battery = merged.get("batteryHealthPct", merged.get("battery_health_pct"))
    if raw_battery is not None and str(raw_battery).strip() != "":
        battery_val = _parse_int(raw_battery)
        if battery_val is None or not (1 <= battery_val <= 100):
            field_errors["batteryHealthPct"] = (
                "Battery health must be between 1% and 100%."
            )

    raw_storage = _extract_scalar(merged.get("storageGb", merged.get("storage_gb")))
    if raw_storage is not None and str(raw_storage).strip() != "":
        storage_val = _parse_int(raw_storage)
        if storage_val is None or storage_val not in ALLOWED_PHONE_STORAGE_GB:
            allowed_str = ", ".join(str(v) for v in sorted(ALLOWED_PHONE_STORAGE_GB))
            field_errors["storageGb"] = f"Storage must be one of {{{allowed_str}}} GB."

    raw_price = merged.get("askingPrice", merged.get("asking_price"))
    if raw_price is not None and str(raw_price).strip() != "":
        try:
            price_val = float(raw_price)
            if price_val <= 0:
                field_errors["askingPrice"] = "Asking price must be greater than 0."
        except (TypeError, ValueError):
            field_errors["askingPrice"] = (
                "Asking price must be a valid positive number."
            )

    valid = len(field_errors) == 0

    required_followups: list[str] = []
    has_damage = bool(merged.get("hasDamage", merged.get("has_damage", False)))
    damage_photo_url = str(merged.get("damagePhotoUrl", "")).strip()
    odometer_photo_url = str(merged.get("odometerPhotoUrl", "")).strip()
    scan_odometer = bool(merged.get("scanOdometer", False))

    if (
        category in ("car", "motorcycle")
        and (mileage_missing or scan_odometer)
        and not odometer_photo_url
    ):
        required_followups.append("odometer_photo")

    if has_damage and not damage_photo_url:
        required_followups.append("damage_photo")

    if not valid:
        recommended_surface = "selling_step_1_detected"
    elif required_followups:
        recommended_surface = "selling_step_2_followup"
    else:
        recommended_surface = "selling_step_3_preview"

    if valid:
        tool_context.state["listing_draft"] = merged
        tool_context.state["stage"] = recommended_surface

    return {
        "status": "success" if valid else "error",
        "valid": valid,
        "field_errors": field_errors,
        "required_followups": required_followups,
        "recommended_surface_id": recommended_surface,
    }


def extract_odometer_reading(
    raw_reading_text: str,
    unit: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Parses digits from an odometer reading, converts miles to kilometers, and checks plausibility.

    Call this tool after reading the digits on an uploaded odometer photo.

    Args:
        raw_reading_text: Raw text or digits read from the odometer display (for example '034,200 km').
        unit: Distance unit shown on the odometer ('km' or 'mi').

    Returns:
        Dictionary with status ('success' or 'error'), mileageKm in kilometers, and target_path.
    """
    text = (raw_reading_text or "").strip()
    if not text:
        return {
            "status": "error",
            "valid": False,
            "error": "Odometer reading text is empty.",
        }

    if re.search(r"-\d", text):
        return {
            "status": "error",
            "valid": False,
            "error": "Odometer reading cannot be negative.",
        }

    cleaned = text.replace(",", "").replace(" ", "")
    match = re.search(r"\d+(?:\.\d+)?", cleaned)
    if not match:
        return {
            "status": "error",
            "valid": False,
            "error": f"Could not extract numeric digits from '{text}'.",
        }

    numeric_value = float(match.group(0))
    normalized_unit = (unit or "km").strip().lower()
    if normalized_unit in ("mi", "mile", "miles") or (
        normalized_unit == "km" and re.search(r"\bmi(?:les?)?\b", text.lower())
    ):
        mileage_km = round(numeric_value * MILES_TO_KM_FACTOR)
    else:
        mileage_km = round(numeric_value)

    if not (0 <= mileage_km <= 600_000):
        return {
            "status": "error",
            "valid": False,
            "error": f"Extracted mileage ({mileage_km} km) is outside plausible bounds [0, 600,000] km.",
        }

    draft = dict(tool_context.state.get("listing_draft", {}))
    draft["mileageKm"] = mileage_km
    tool_context.state["listing_draft"] = draft

    return {
        "status": "success",
        "valid": True,
        "mileageKm": mileage_km,
        "unit": "km",
        "target_path": "/details/mileageKm",
    }


def _brand_multiplier(brand: str) -> float:
    b = (brand or "").strip().lower()
    if b in PREMIUM_BRANDS:
        return 1.35
    if b in MID_HIGH_BRANDS:
        return 1.12
    return 1.0


def estimate_price_and_build_preview(
    user_asking_price: float,
    currency: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Computes a deterministic market price range and builds the complete listing preview payload.

    Call this tool once all required item details and follow-ups are complete to prepare Step 3 (Listing Preview).

    Args:
        user_asking_price: User-specified asking price, or 0.0 when the user has not chosen a custom price yet.
        currency: ISO 4217 currency code such as 'USD' or 'COP'.

    Returns:
        Dictionary with status, minPrice, suggestedPrice, maxPrice, askingPrice, currency, rationale, generatedTitle, generatedDescription, specs, and missingChecklist.
    """
    draft: dict[str, Any] = dict(tool_context.state.get("listing_draft", {}))
    cat = _normalize_category(str(draft.get("category", "car")))
    if cat == "unsupported":
        cat = "car"

    item_brand = str(draft.get("brand", "Generic")).strip() or "Generic"
    item_model = str(draft.get("model", "Model")).strip() or "Model"
    item_color = str(draft.get("color", "")).strip()
    parsed_year = _parse_int(draft.get("year", 2021)) or 2021
    age = max(0, 2026 - parsed_year)

    is_damaged = bool(draft.get("hasDamage", False))
    dmg_notes = str(draft.get("damageNotes", "")).strip()
    owner_str = str(_extract_scalar(draft.get("ownersCount", ["1"])) or "1")
    papers_ok = bool(draft.get("papersUpToDate", True))
    is_unlocked = bool(draft.get("unlocked", True))
    is_ev = bool(draft.get("isEv", False))

    km_val = _parse_int(draft.get("mileageKm"))
    cc_val = _parse_int(draft.get("engineCc"))
    storage_val = _parse_int(_extract_scalar(draft.get("storageGb")))
    battery_val = _parse_int(draft.get("batteryHealthPct"))

    mult = _brand_multiplier(item_brand)
    specs: list[dict[str, str]] = [{"label": "Year", "value": str(parsed_year)}]
    rationale_parts: list[str] = [f"Based on a {parsed_year} {item_brand} {item_model}"]

    if cat == "car":
        base_usd = 24000.0 * mult * (1.12 if is_ev else 1.0)
        depreciated = base_usd * (0.91**age)
        effective_km = km_val if km_val is not None else 45000
        expected_km = max(12000, age * 14000)
        km_delta = effective_km - expected_km
        km_factor = max(0.60, min(1.12, 1.0 - (km_delta / 250000.0)))
        estimated_usd = depreciated * km_factor * (0.92 if not papers_ok else 1.0)
        specs.append({"label": "Mileage", "value": f"{effective_km:,} km"})
        if is_ev:
            specs.append({"label": "Powertrain", "value": "Electric (EV)"})
            if battery_val is not None:
                specs.append({"label": "Battery Health", "value": f"{battery_val}%"})
        elif cc_val is not None:
            specs.append({"label": "Engine", "value": f"{cc_val:,} cc"})
        specs.append(
            {
                "label": "Owners",
                "value": "1st Owner" if owner_str == "1" else f"{owner_str} Owners",
            }
        )
        specs.append(
            {
                "label": "Papers",
                "value": "Up to date" if papers_ok else "Pending renewal",
            }
        )
        rationale_parts.append(f"with {effective_km:,} km")
    elif cat == "motorcycle":
        cc_effective = cc_val if cc_val is not None else 400
        cc_factor = max(0.55, min(2.2, (cc_effective / 500.0) ** 0.55))
        base_usd = 6800.0 * mult * cc_factor
        depreciated = base_usd * (0.89**age)
        effective_km = km_val if km_val is not None else 18000
        km_factor = max(0.60, min(1.10, 1.0 - (effective_km / 140000.0)))
        estimated_usd = depreciated * km_factor
        specs.append({"label": "Mileage", "value": f"{effective_km:,} km"})
        specs.append({"label": "Engine", "value": f"{cc_effective:,} cc"})
        specs.append(
            {
                "label": "Owners",
                "value": "1st Owner" if owner_str == "1" else f"{owner_str} Owners",
            }
        )
        specs.append(
            {
                "label": "Papers",
                "value": "Up to date" if papers_ok else "Pending renewal",
            }
        )
        rationale_parts.append(f"with {effective_km:,} km and {cc_effective} cc engine")
    else:
        eff_storage = storage_val if storage_val is not None else 256
        eff_battery = battery_val if battery_val is not None else 90
        storage_bonus = {
            32: 0.80,
            64: 0.88,
            128: 1.0,
            256: 1.12,
            512: 1.26,
            1024: 1.42,
            2048: 1.58,
        }.get(eff_storage, 1.0)
        battery_factor = max(0.75, min(1.05, 0.70 + (eff_battery / 100.0) * 0.35))
        base_usd = 820.0 * mult * storage_bonus
        depreciated = base_usd * (0.82**age)
        estimated_usd = depreciated * battery_factor * (1.0 if is_unlocked else 0.90)
        specs.append({"label": "Storage", "value": f"{eff_storage} GB"})
        specs.append({"label": "Battery Health", "value": f"{eff_battery}%"})
        specs.append(
            {
                "label": "Carrier",
                "value": "Unlocked" if is_unlocked else "Carrier Locked",
            }
        )
        rationale_parts.append(
            f"with {eff_storage} GB storage and {eff_battery}% battery health"
        )

    if is_damaged:
        estimated_usd *= 0.86
        rationale_parts.append("adjusted for reported cosmetic/functional damage")
    else:
        rationale_parts.append("in clean condition with no reported damage")

    curr = (currency or "USD").strip().upper()
    fx = USD_TO_COP_RATE if curr == "COP" else 1
    round_step = 50000 if curr == "COP" else (10 if cat == "phone" else 100)

    def _round_price(val: float) -> int:
        scaled = max(float(round_step), val * fx)
        return round(scaled / round_step) * round_step

    suggested_price = _round_price(estimated_usd)
    min_price = max(round_step, _round_price(estimated_usd * 0.91))
    max_price = max(suggested_price + round_step, _round_price(estimated_usd * 1.08))
    if min_price >= suggested_price:
        min_price = max(1, suggested_price - round_step)

    asking_price = (
        round(float(user_asking_price))
        if user_asking_price and user_asking_price > 0
        else suggested_price
    )

    rationale = ", ".join(rationale_parts) + "."
    headline_detail = (
        f"{km_val:,} km"
        if cat in ("car", "motorcycle") and km_val is not None
        else (f"{storage_val or 256} GB" if cat == "phone" else item_color)
    )
    generated_title = f"{parsed_year} {item_brand} {item_model}".strip()
    if headline_detail:
        generated_title = f"{generated_title} — {headline_detail}"

    condition_clause = (
        f"Note on condition: {dmg_notes or 'Visible wear documented in photos.'}"
        if is_damaged
        else "Clean condition with no reported damage."
    )
    spec_summary = ", ".join(f"{s['label']}: {s['value']}" for s in specs)
    generated_description = (
        f"Well-maintained {parsed_year} {item_brand} {item_model}"
        f"{f' in {item_color}' if item_color else ''}. "
        f"Key specifications: {spec_summary}. {condition_clause}"
    )

    image_urls: list[str] = []
    for key in ("imageUrl", "odometerPhotoUrl", "damagePhotoUrl"):
        val = draft.get(key)
        if val and str(val) not in image_urls:
            image_urls.append(str(val))
    if not image_urls:
        image_urls.append("http://10.0.2.2:8000/uploads/demo_item.jpg")

    missing_checklist: list[dict[str, Any]] = [
        {"item": "Main item photo uploaded", "completed": True},
        {"item": "Category-specific specifications verified", "completed": True},
    ]
    if cat in ("car", "motorcycle"):
        missing_checklist.append(
            {
                "item": "Mileage verified",
                "completed": km_val is not None or bool(draft.get("odometerPhotoUrl")),
            }
        )
    if is_damaged:
        missing_checklist.append(
            {
                "item": "Damage close-up photo attached",
                "completed": bool(draft.get("damagePhotoUrl")),
            }
        )

    result: dict[str, Any] = {
        "status": "success",
        "category": cat,
        "minPrice": min_price,
        "suggestedPrice": suggested_price,
        "maxPrice": max_price,
        "askingPrice": asking_price,
        "currency": curr,
        "rationale": rationale,
        "generatedTitle": generated_title,
        "generatedDescription": generated_description,
        "specs": specs,
        "missingChecklist": missing_checklist,
        "imageUrls": image_urls,
        "recommended_surface_id": "selling_step_3_preview",
    }
    tool_context.state["price_estimate"] = result
    tool_context.state["stage"] = "selling_step_3_preview"
    return result
