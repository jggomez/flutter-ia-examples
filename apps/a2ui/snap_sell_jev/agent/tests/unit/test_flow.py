"""End-to-end wizard turns through SellingFlow with a scripted Jev and writer."""

from __future__ import annotations

from typing import Any

import pytest

from app.flow import SellingFlow, TurnInput
from tests.unit.fakes import FakeJev, FakeWriter, choice, level, noul

PHOTO = b"\xff\xd8\xff\xe0fake-jpeg"
URL = "http://10.0.2.2:8000/uploads/car.jpg"


def _create(out) -> dict[str, Any]:
    assert len(out.messages) == 1
    return out.messages[0]["createSurface"]


def _ids(create: dict[str, Any]) -> set[str]:
    return {c["id"] for c in create["components"]}


def _component(create: dict[str, Any], cid: str) -> dict[str, Any]:
    return next(c for c in create["components"] if c["id"] == cid)


def _action(name: str, **context: Any) -> dict[str, Any]:
    return {"name": name, "surfaceId": "s", "context": context}


CAR_DETAILS = {
    "category": "car",
    "isEv": False,
    "brand": "Mazda",
    "model": "CX-30",
    "year": "2021",
    "color": "Soul Red",
    "mileageKm": "34200",
    "engineCc": "2000",
    "ownersCount": ["1"],
    "papersUpToDate": True,
    "hasDamage": False,
}


async def _start(flow: SellingFlow) -> tuple[dict[str, Any], Any]:
    out = await flow.handle({}, TurnInput(photo=PHOTO, image_url=URL))
    return out.state, out


@pytest.mark.asyncio
async def test_photo_turn_builds_detected_car_surface_from_jev_and_gemini() -> None:
    jev, writer = FakeJev(), FakeWriter()
    state, out = await _start(SellingFlow(jev, writer))

    create = _create(out)
    assert create["surfaceId"] == "selling_step_1_detected"
    card = _component(create, "detected_card")
    assert card["confidence"] == 0.94  # Jev's calibrated probability
    assert card["isEv"] is False
    assert "engineCc_field" in _ids(create)
    assert "batteryRangeKm_field" not in _ids(create)
    assert create["dataModel"]["detected"]["brand"] == "Mazda"  # written by Gemini
    assert create["dataModel"]["detected"]["imageUrl"] == URL
    # one Jev request with the photo, all photo questions at once
    assert len(jev.calls) == 1 and jev.calls[0]["photo"] == PHOTO
    assert [t["question"] for t in out.trace if t["stage"] == "photo"] == [
        "category",
        "is_ev",
        "visible_damage",
        "photo_quality",
    ]
    assert any(t["stage"] == "form" for t in out.trace)
    assert state["stage"] == "selling_step_1_detected"


@pytest.mark.asyncio
async def test_ev_and_damage_change_the_blocks() -> None:
    jev = FakeJev(is_ev=noul(0.9), visible_damage=noul(0.8))
    _, out = await _start(SellingFlow(jev, FakeWriter()))
    create = _create(out)
    assert "batteryRangeKm_field" in _ids(create)
    assert "engineCc_field" not in _ids(create)
    # damage seen by Jev: damage question first, with a notice
    questions = _component(create, "questions_column")["children"]
    assert questions[1] == "hasDamage_field"
    assert create["dataModel"]["details"]["hasDamage"] is True


@pytest.mark.asyncio
async def test_phone_gets_phone_questions() -> None:
    jev = FakeJev(category=choice({"phone": 0.96, "car": 0.04}))
    _, out = await _start(SellingFlow(jev, FakeWriter()))
    create = _create(out)
    assert "storageGb_field" in _ids(create)
    assert "mileageKm_field" not in _ids(create)
    assert "isEv" not in _component(create, "detected_card")


@pytest.mark.asyncio
async def test_form_follows_jev_field_answers_and_is_kept_on_send_back() -> None:
    jev = FakeJev(
        field_originalParts=noul(0.9),
        field_restoration=noul(0.8),
        field_ownersCount=noul(0.1),
    )
    flow = SellingFlow(jev, FakeWriter())
    state, out = await _start(flow)
    create = _create(out)
    assert {"originalParts_field", "restoration_field"} <= _ids(create)
    assert "ownersCount_field" not in _ids(create)
    assert create["dataModel"]["details"]["restoration"] == ["none"]
    # the submit button sends exactly the fields that were shown
    ctx = _component(create, "continue_btn")["action"]["event"]["context"]
    assert {"originalParts", "restoration", "mileageKm"} <= set(ctx)
    assert "ownersCount" not in ctx
    assert state["form_fields"][-1] == "hasDamage"

    # an invalid submit re-renders the SAME form, with the user's values kept
    bad = {**CAR_DETAILS, "mileageKm": "-5", "restoration": ["full"]}
    again = await flow.handle(state, TurnInput(action=_action("submit_detected_details", **bad)))
    create = _create(again)
    assert {"originalParts_field", "restoration_field"} <= _ids(create)
    assert create["dataModel"]["details"]["restoration"] == ["full"]


@pytest.mark.asyncio
async def test_unsupported_item() -> None:
    jev = FakeJev(category=choice({"unsupported": 0.9, "car": 0.1}))
    _, out = await _start(SellingFlow(jev, FakeWriter()))
    assert _create(out)["surfaceId"] == "selling_unsupported"


@pytest.mark.asyncio
async def test_blurry_photo_adds_notice() -> None:
    jev = FakeJev(photo_quality=level(0, 4))
    _, out = await _start(SellingFlow(jev, FakeWriter()))
    assert "notice_0" in _ids(_create(out))


@pytest.mark.asyncio
async def test_clean_car_goes_straight_to_preview_with_condition_price() -> None:
    jev, writer = FakeJev(condition=level(4, 5)), FakeWriter()
    flow = SellingFlow(jev, writer)
    state, _ = await _start(flow)
    out = await flow.handle(
        state, TurnInput(action=_action("submit_detected_details", **CAR_DETAILS))
    )

    create = _create(out)
    assert create["surfaceId"] == "selling_step_3_preview"
    assert create["dataModel"]["preview"]["title"] == "2021 Mazda CX-30"
    assert "Like new" in create["dataModel"]["pricing"]["rationale"]
    price = _component(create, "price_range_card")
    assert price["feedback"]["@call"] == "priceFeedback"
    assert price["suggestedPrice"] % 100 == 0
    assert (
        writer.listing_facts is not None
        and writer.listing_facts["condition"] == "Like new"
    )


@pytest.mark.asyncio
async def test_implausible_details_are_sent_back_once() -> None:
    flow = SellingFlow(FakeJev(plausible=level(0, 4)), FakeWriter())
    state, _ = await _start(flow)
    submit = TurnInput(action=_action("submit_detected_details", **CAR_DETAILS))

    first = await flow.handle(state, submit)
    assert _create(first)["surfaceId"] == "selling_step_1_detected"
    assert "notice_0" in _ids(_create(first))
    assert _create(first)["dataModel"]["details"]["mileageKm"] == "34200"

    second = await flow.handle(first.state, submit)
    assert _create(second)["surfaceId"] == "selling_step_3_preview"


@pytest.mark.asyncio
async def test_invalid_fields_are_reported_by_code_without_asking_jev() -> None:
    jev = FakeJev()
    flow = SellingFlow(jev, FakeWriter())
    state, _ = await _start(flow)
    bad = {**CAR_DETAILS, "engineCc": "20"}
    out = await flow.handle(
        state, TurnInput(action=_action("submit_detected_details", **bad))
    )
    assert _create(out)["surfaceId"] == "selling_step_1_detected"
    assert len(jev.calls) == 1  # only the photo turn


@pytest.mark.asyncio
async def test_damage_and_odometer_followup_full_path() -> None:
    jev, writer = FakeJev(mileage_suspicious=noul(0.9)), FakeWriter()
    flow = SellingFlow(jev, writer)
    state, _ = await _start(flow)
    details = {**CAR_DETAILS, "hasDamage": True}
    out = await flow.handle(
        state, TurnInput(action=_action("submit_detected_details", **details))
    )
    create = _create(out)
    assert create["surfaceId"] == "selling_step_2_followup"
    assert {"odometer_photo_request", "damage_photo_request"} <= _ids(create)

    # submitting without photos keeps the user on step 2
    early = await flow.handle(out.state, TurnInput(action=_action("submit_followup")))
    assert _create(early)["surfaceId"] == "selling_step_2_followup"

    odo = await flow.handle(
        out.state,
        TurnInput(
            action=_action("upload_followup_photo", requestType="odometer"),
            photo=PHOTO,
            image_url="http://x/odo.jpg",
        ),
    )
    assert (
        _create(odo)["dataModel"]["followup"]["odometerPhotoUrl"] == "http://x/odo.jpg"
    )
    assert odo.state["listing_draft"]["mileageKm"] == 34200

    dmg = await flow.handle(
        odo.state,
        TurnInput(
            action=_action("upload_followup_photo", requestType="damage"),
            photo=PHOTO,
            image_url="http://x/dmg.jpg",
        ),
    )
    assert dmg.trace[0]["question"] == "damage_documented"

    final = await flow.handle(
        dmg.state,
        TurnInput(action=_action("submit_followup", damageNotes="Scratch on door")),
    )
    create = _create(final)
    assert create["surfaceId"] == "selling_step_3_preview"
    assert "http://x/dmg.jpg" in _component(create, "listing_preview_card")["imageUrls"]


@pytest.mark.asyncio
async def test_unclear_damage_photo_is_not_accepted() -> None:
    flow = SellingFlow(FakeJev(damage_documented=noul(0.1)), FakeWriter())
    state = {"listing_draft": {"category": "car"}, "need_damage": True}
    out = await flow.handle(
        state,
        TurnInput(
            action=_action("upload_followup_photo", requestType="damage"), photo=PHOTO
        ),
    )
    assert "damagePhotoUrl" not in out.state["listing_draft"]


@pytest.mark.asyncio
async def test_request_odometer_scan_shows_only_odometer() -> None:
    flow = SellingFlow(FakeJev(), FakeWriter())
    out = await flow.handle(
        {}, TurnInput(action=_action("request_odometer_scan", category="car"))
    )
    ids = _ids(_create(out))
    assert "odometer_photo_request" in ids
    assert "damage_photo_request" not in ids


@pytest.mark.asyncio
async def test_copy_falls_back_to_deterministic_text_when_gemini_fails() -> None:
    writer = FakeWriter()
    writer.fail_copy = True
    flow = SellingFlow(FakeJev(), writer)
    state, _ = await _start(flow)
    out = await flow.handle(
        state, TurnInput(action=_action("submit_detected_details", **CAR_DETAILS))
    )
    assert "Mazda" in _create(out)["dataModel"]["preview"]["title"]


@pytest.mark.asyncio
async def test_publish() -> None:
    flow = SellingFlow(FakeJev(), FakeWriter())
    out = await flow.handle(
        {},
        TurnInput(
            action=_action(
                "publish_listing", title="T", askingPrice=100, currency="USD"
            )
        ),
    )
    assert _create(out)["surfaceId"] == "selling_step_4_published"
    assert out.state["stage"] == "selling_step_4_published"


@pytest.mark.asyncio
async def test_missing_jev_key_is_an_explicit_error_not_a_guess() -> None:
    jev = FakeJev()
    jev.fail = True
    out = await SellingFlow(jev, FakeWriter()).handle({}, TurnInput(photo=PHOTO))
    assert out.messages == []
    assert "JEV_API_KEY" in out.text
    assert out.state == {}
