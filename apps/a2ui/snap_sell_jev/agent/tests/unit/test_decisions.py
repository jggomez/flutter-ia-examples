"""Thresholds and ranking walks in app.decisions (pure functions, no network)."""

from __future__ import annotations

import pytest

from app import decisions, field_bank
from tests.unit.fakes import DEFAULT_ANSWERS, choice, level, noul, score


def _photo(**overrides):
    return decisions.decide_photo({**DEFAULT_ANSWERS, **overrides})


def test_photo_questions_cover_every_decision() -> None:
    questions = decisions.photo_questions()
    core = {"category", "is_ev", "visible_damage", "photo_quality"}
    field_questions = {f"field_{s.key}" for s in field_bank.all_candidates()}
    assert set(questions) == core | field_questions
    assert all(questions[q]["type"] == "noul" for q in field_questions)
    assert set(questions["category"]["criteria"]) == set(decisions.CATEGORY_OPTIONS)
    assert questions["photo_quality"]["type"] == "score"


def test_top_category_is_used_with_its_probability_as_confidence() -> None:
    d = _photo()
    assert d.category == "car"
    assert d.confidence == 0.94
    assert d.trace[0].question == "category"


def test_low_category_confidence_falls_back_to_unsupported() -> None:
    d = _photo(category=choice({"car": 0.35, "motorcycle": 0.33, "phone": 0.32}))
    assert d.category == "unsupported"
    assert "unsupported" in d.trace[0].outcome


def test_unknown_options_are_skipped_when_walking_the_ranking() -> None:
    d = _photo(category=choice({"boat": 0.9, "phone": 0.08, "car": 0.02}))
    assert d.category == "unsupported"  # phone is first allowed but below 40 %


@pytest.mark.parametrize(("p", "expected"), [(0.49, False), (0.5, True)])
def test_ev_threshold(p: float, expected: bool) -> None:
    assert _photo(is_ev=noul(p)).is_ev is expected


def test_ev_is_ignored_for_phones() -> None:
    d = _photo(category=choice({"phone": 0.9, "car": 0.1}), is_ev=noul(0.99))
    assert d.is_ev is False


@pytest.mark.parametrize(("p", "expected"), [(0.59, False), (0.6, True)])
def test_damage_threshold_is_stricter_than_yes(p: float, expected: bool) -> None:
    assert _photo(visible_damage=noul(p)).has_damage is expected


def test_blurry_photo_shows_retake_hint() -> None:
    assert _photo(photo_quality=level(0, 4)).retake_hint is True
    assert _photo(photo_quality=score([0, 0.5, 0.5, 0])).retake_hint is False  # 1.5


def test_details_sent_back_once_when_implausible() -> None:
    answers = {**DEFAULT_ANSWERS, "plausible": level(0, 4)}
    first = decisions.decide_details(answers, already_warned=False, has_mileage=True)
    again = decisions.decide_details(answers, already_warned=True, has_mileage=True)
    assert first.send_back is True
    assert again.send_back is False


def test_suspicious_mileage_requests_odometer_only_when_typed() -> None:
    answers = {**DEFAULT_ANSWERS, "mileage_suspicious": noul(0.8)}
    typed = decisions.decide_details(answers, already_warned=False, has_mileage=True)
    missing = decisions.decide_details(answers, already_warned=False, has_mileage=False)
    assert typed.want_odometer_photo is True
    assert missing.want_odometer_photo is False


def test_condition_level_maps_to_price_factor() -> None:
    answers = {**DEFAULT_ANSWERS, "condition": level(4, 5)}
    d = decisions.decide_details(answers, already_warned=False, has_mileage=True)
    assert d.condition_level == 4
    assert decisions.CONDITION_PRICE_FACTOR[d.condition_level] > 1


def test_phone_details_do_not_ask_about_mileage() -> None:
    assert "mileage_suspicious" not in decisions.details_questions("phone")
    assert "mileage_suspicious" in decisions.details_questions("car")


def test_damage_photo_decision() -> None:
    ok, entry = decisions.decide_damage_photo({"damage_documented": noul(0.2)})
    assert ok is False
    assert entry.outcome == "retake requested"


def test_trace_entries_serialize_with_rounded_probability() -> None:
    entry = _photo().trace[0].to_dict()
    assert entry == {
        "question": "category",
        "kind": "choice",
        "answer": "car",
        "probability": 0.94,
        "outcome": "stage for 'car'",
    }


# ---------------------------------------------------------------------------
# The step-1 form is decided per photo
# ---------------------------------------------------------------------------


def _form(photo_overrides=None, **field_probs):
    answers = {**DEFAULT_ANSWERS, **(photo_overrides or {})}
    answers.update({f"field_{k}": noul(p) for k, p in field_probs.items()})
    return decisions.decide_form(answers, decisions.decide_photo(answers))


def test_two_cars_get_different_forms() -> None:
    classic = _form(originalParts=0.9, restoration=0.8, ownersCount=0.7)
    new_car = _form(warrantyActive=0.9, transmission=0.7)
    assert {"originalParts", "restoration"} <= set(classic.fields)
    assert "warrantyActive" not in classic.fields
    assert "warrantyActive" in new_car.fields
    assert "originalParts" not in new_car.fields
    # the base is always there
    for form in (classic, new_car):
        assert form.fields[0] == "mileageKm" and form.fields[-1] == "hasDamage"


def test_extra_fields_are_capped_and_ranked_by_probability() -> None:
    form = _form(
        ownersCount=0.55, papersUpToDate=0.6, transmission=0.9,
        serviceHistory=0.8, tiresCondition=0.7, modifications=0.65,
    )
    extras = [f for f in form.fields if f not in ("mileageKm", "engineCc", "hasDamage")]
    assert extras == ["transmission", "serviceHistory", "tiresCondition", "modifications"]
    skipped = {t.question: t.outcome for t in form.trace}
    assert skipped["field_papersUpToDate"].startswith("skipped: only")


def test_fields_below_threshold_are_not_shown() -> None:
    form = _form(ownersCount=0.49)
    assert form.fields == ["mileageKm", "engineCc", "hasDamage"]


def test_visible_damage_moves_damage_question_first_with_notice() -> None:
    form = _form({"visible_damage": noul(0.85)})
    assert form.fields[0] == "hasDamage"
    assert form.notices


def test_fields_of_other_categories_are_never_shown() -> None:
    phone = {"category": choice({"phone": 0.95, "car": 0.05})}
    form = _form(phone, includesHelmet=0.99, screenCondition=0.9)
    assert "includesHelmet" not in form.fields
    assert form.fields == ["storageGb", "screenCondition", "hasDamage"]


def test_ev_gets_battery_fields_instead_of_engine() -> None:
    form = _form({"is_ev": noul(0.9)}, batteryHealthPct=0.8)
    assert "engineCc" not in form.fields
    assert {"batteryRangeKm", "batteryHealthPct"} <= set(form.fields)
