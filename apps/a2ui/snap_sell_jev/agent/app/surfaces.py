"""Code assembles the A2UI v1.0 trees ("code assembles" in jev2ui's pipeline).

Each builder returns the v1.0 wire messages for one stage. The *shape* is fixed
here (same structure as `contracts/examples/1.0`); Jev's decisions only switch
blocks on or off, and Gemini's output only fills `dataModel` values. Every
payload is checked with `validate_a2ui_payload` before it is sent.
"""

from __future__ import annotations

from typing import Any

from app import field_bank
from app.catalog import SNAP_SELL_CATALOG_ID, validate_a2ui_payload

STEP_LABELS = ["Detected", "Follow-up", "Preview", "Published"]
CATEGORY_NOUN = {"car": "vehicle", "motorcycle": "motorcycle", "phone": "smartphone"}


def _surface(
    surface_id: str, components: list[dict[str, Any]], data: dict[str, Any] | None
) -> list[dict[str, Any]]:
    create: dict[str, Any] = {
        "surfaceId": surface_id,
        "catalogId": SNAP_SELL_CATALOG_ID,
        "sendDataModel": True,
        "components": components,
    }
    if data is not None:
        create["dataModel"] = data
    messages = [{"version": "1.0", "createSurface": create}]
    validate_a2ui_payload(messages)
    return messages


def _progress(step: int, subtitle: str) -> dict[str, Any]:
    return {
        "id": "step_progress",
        "component": "StepProgress",
        "currentStep": step,
        "totalSteps": 4,
        "stepLabels": STEP_LABELS,
        "subtitle": subtitle,
    }


def _text(cid: str, text: str) -> dict[str, Any]:
    return {"id": cid, "component": "Text", "variant": "body", "text": text}


def _button(
    cid: str, label: str, action: str, context: dict[str, Any], variant: str = "primary"
) -> list[dict[str, Any]]:
    return [
        {"id": f"{cid}_label", "component": "Text", "text": label},
        {
            "id": cid,
            "component": "Button",
            "variant": variant,
            "child": f"{cid}_label",
            "action": {"event": {"name": action, "context": context}},
        },
    ]


def _path(path: str) -> dict[str, str]:
    return {"@path": path}


def detected(
    *,
    category: str,
    confidence: float,
    is_ev: bool,
    item: dict[str, Any],
    fields: list[str],
    details: dict[str, Any],
    notices: list[str],
) -> list[dict[str, Any]]:
    """`selling_step_1_detected`: the form is the list of `fields` Jev chose for this photo."""
    vehicle = category in ("car", "motorcycle")
    card_fields = [
        {
            "key": key,
            "label": label,
            "value": _path(f"/detected/{key}"),
            "editable": True,
        }
        for key, label in (
            ("brand", "Brand"),
            ("model", "Model"),
            ("year", "Year / Generation"),
            ("color", "Color"),
        )
    ]
    card: dict[str, Any] = {
        "id": "detected_card",
        "component": "DetectedItemCard",
        "category": category,
        "imageUrl": _path("/detected/imageUrl"),
        "confidence": confidence,
        "summary": _path("/detected/summary"),
        "fields": card_fields,
    }
    if vehicle:
        card["isEv"] = is_ev

    questions: list[dict[str, Any]] = []
    for key in fields:
        questions.append(field_bank.component_for(field_bank.BANK[key], f"{key}_field"))
        if key == "mileageKm":
            questions += _button(
                "scan_odometer_btn",
                "Or scan odometer photo",
                "request_odometer_scan",
                {"category": category},
                variant="borderless",
            )
    context: dict[str, Any] = {
        "category": category,
        **{k: _path(f"/detected/{k}") for k in ("brand", "model", "year", "color")},
        **{k: _path(f"/details/{k}") for k in fields},
    }
    if vehicle:
        context["isEv"] = is_ev
    name = " ".join(str(item.get(k, "")).strip() for k in ("year", "brand", "model")).strip()
    heading = f"### About your {name}" if name else f"### About your {CATEGORY_NOUN[category]}"

    notice_ids = [f"notice_{i}" for i in range(len(notices))]
    components = [
        {
            "id": "root",
            "component": "Column",
            "justify": "start",
            "align": "stretch",
            "children": [
                "step_progress",
                *notice_ids,
                "detected_card",
                "questions_card",
                "continue_btn",
            ],
        },
        _progress(
            1,
            f"Review the detected {CATEGORY_NOUN[category]} and answer what the photo cannot show.",
        ),
        *(
            _text(nid, f"⚠️ {text}")
            for nid, text in zip(notice_ids, notices, strict=True)
        ),
        card,
        {"id": "questions_card", "component": "Card", "child": "questions_column"},
        {
            "id": "questions_column",
            "component": "Column",
            "justify": "start",
            "align": "stretch",
            "children": [
                "questions_heading",
                *(q["id"] for q in questions if q["component"] != "Text"),
            ],
        },
        _text("questions_heading", heading),
        *questions,
        *_button("continue_btn", "Continue", "submit_detected_details", context),
    ]
    data = {
        "detected": {
            k: item.get(k, "")
            for k in ("imageUrl", "summary", "brand", "model", "year", "color")
        },
        "details": details,
    }
    return _surface("selling_step_1_detected", components, data)


def unsupported() -> list[dict[str, Any]]:
    components = [
        {"id": "root", "component": "Card", "child": "unsupported_column"},
        {
            "id": "unsupported_column",
            "component": "Column",
            "justify": "center",
            "align": "center",
            "children": [
                "warning_icon",
                "unsupported_title",
                "unsupported_body",
                "try_again_btn",
            ],
        },
        {"id": "warning_icon", "component": "Icon", "name": "warning"},
        _text("unsupported_title", "### Category Not Supported Yet"),
        _text(
            "unsupported_body",
            "Snap & Sell currently supports Cars, Motorcycles, and Smartphones. "
            "Please snap or choose a photo of one of those items to generate a listing.",
        ),
        *_button("try_again_btn", "Try Another Photo", "start_new_listing", {}),
    ]
    return _surface("selling_unsupported", components, None)


# ---------------------------------------------------------------------------
# Step 2
# ---------------------------------------------------------------------------


def followup(
    *,
    need_odometer: bool,
    need_damage: bool,
    followup_data: dict[str, Any],
    notices: list[str],
) -> list[dict[str, Any]]:
    """`selling_step_2_followup`: only the photo requests code + Jev asked for."""
    blocks: list[dict[str, Any]] = []
    if need_odometer:
        blocks.append(
            {
                "id": "odometer_photo_request",
                "component": "PhotoRequest",
                "requestType": "odometer",
                "title": "Odometer Photo",
                "instructions": "Snap a clear photo of the dashboard odometer. Gemini will read the mileage.",
                "actionName": "upload_followup_photo",
                "targetPath": "/followup/odometerPhotoUrl",
                "previewUrl": _path("/followup/odometerPhotoUrl"),
                "required": True,
            }
        )
    if need_damage:
        blocks.append(
            {
                "id": "damage_photo_request",
                "component": "PhotoRequest",
                "requestType": "damage",
                "title": "Close-up of Reported Damage",
                "instructions": "Take a well-lit close-up of the scratch or dent so buyers have full transparency.",
                "actionName": "upload_followup_photo",
                "targetPath": "/followup/damagePhotoUrl",
                "previewUrl": _path("/followup/damagePhotoUrl"),
                "required": True,
            }
        )
        blocks.append(
            {
                "id": "damage_notes_field",
                "component": "TextField",
                "label": "Brief description of the damage",
                "variant": "longText",
                "value": _path("/followup/damageNotes"),
            }
        )
    notice_ids = [f"notice_{i}" for i in range(len(notices))]
    parts = []
    if need_odometer:
        parts.append("read the odometer")
    if need_damage:
        parts.append("document the reported damage")
    components = [
        {
            "id": "root",
            "component": "Column",
            "justify": "start",
            "align": "stretch",
            "children": [
                "step_progress",
                *notice_ids,
                *(b["id"] for b in blocks),
                "continue_followup_btn",
            ],
        },
        _progress(2, f"Add quick photos so we can {' and '.join(parts) or 'finish'}."),
        *(_text(nid, text) for nid, text in zip(notice_ids, notices, strict=True)),
        *blocks,
        *_button(
            "continue_followup_btn",
            "Generate Listing Preview",
            "submit_followup",
            {
                "odometerPhotoUrl": _path("/followup/odometerPhotoUrl"),
                "damagePhotoUrl": _path("/followup/damagePhotoUrl"),
                "damageNotes": _path("/followup/damageNotes"),
            },
        ),
    ]
    data = {
        "followup": {
            "odometerPhotoUrl": followup_data.get("odometerPhotoUrl", ""),
            "damagePhotoUrl": followup_data.get("damagePhotoUrl", ""),
            "damageNotes": followup_data.get("damageNotes", ""),
        }
    }
    return _surface("selling_step_2_followup", components, data)


# ---------------------------------------------------------------------------
# Steps 3 and 4
# ---------------------------------------------------------------------------


def preview(
    *, estimate: dict[str, Any], title: str, description: str, rationale: str
) -> list[dict[str, Any]]:
    """`selling_step_3_preview`: numbers from code, copy from Gemini."""
    lo, mid, hi = estimate["minPrice"], estimate["suggestedPrice"], estimate["maxPrice"]
    currency, category = estimate["currency"], estimate["category"]
    components = [
        {
            "id": "root",
            "component": "Column",
            "justify": "start",
            "align": "stretch",
            "children": ["step_progress", "price_range_card", "listing_preview_card"],
        },
        _progress(
            3,
            "Review your generated listing and adjust the asking price before publishing.",
        ),
        {
            "id": "price_range_card",
            "component": "PriceRange",
            "minPrice": lo,
            "suggestedPrice": mid,
            "maxPrice": hi,
            "selectedPrice": _path("/pricing/askingPrice"),
            "currency": currency,
            "rationale": _path("/pricing/rationale"),
            "feedback": {
                "@call": "priceFeedback",
                "args": {
                    "askingPrice": _path("/pricing/askingPrice"),
                    "minPrice": lo,
                    "suggestedPrice": mid,
                    "maxPrice": hi,
                },
            },
        },
        {
            "id": "listing_preview_card",
            "component": "ListingPreview",
            "title": _path("/preview/title"),
            "description": _path("/preview/description"),
            "category": category,
            "price": _path("/pricing/askingPrice"),
            "currency": currency,
            "imageUrls": estimate["imageUrls"],
            "specs": estimate["specs"],
            "missingChecklist": estimate["missingChecklist"],
            "publishAction": {
                "event": {
                    "name": "publish_listing",
                    "context": {
                        "title": _path("/preview/title"),
                        "description": _path("/preview/description"),
                        "askingPrice": _path("/pricing/askingPrice"),
                        "currency": currency,
                        "category": category,
                    },
                }
            },
        },
    ]
    data = {
        "pricing": {"askingPrice": estimate["askingPrice"], "rationale": rationale},
        "preview": {"title": title, "description": description},
    }
    return _surface("selling_step_3_preview", components, data)


def published(*, title: str, price: Any, currency: str) -> list[dict[str, Any]]:
    components = [
        {
            "id": "root",
            "component": "Column",
            "justify": "start",
            "align": "stretch",
            "children": ["step_progress", "published_card"],
        },
        _progress(4, "Your listing is live."),
        {"id": "published_card", "component": "Card", "child": "published_column"},
        {
            "id": "published_column",
            "component": "Column",
            "justify": "center",
            "align": "center",
            "children": [
                "published_icon",
                "published_title",
                "published_summary",
                "new_listing_btn",
            ],
        },
        {"id": "published_icon", "component": "Icon", "name": "check"},
        _text("published_title", "### Listing Published"),
        _text("published_summary", f"{title} — {price} {currency}"),
        *_button("new_listing_btn", "Sell Another Item", "start_new_listing", {}),
    ]
    return _surface("selling_step_4_published", components, None)
