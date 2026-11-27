"""The questions Snap & Sell asks Jev, and how code turns the answers into decisions.

This is the "grammar" of the Jev variant (jev2ui keeps it in `grammar/*.md`):
Jev only ranks options and gives probabilities; code walks the ranking to the
first *allowed* option and applies fixed thresholds. Every decision is kept
with its probability in a trace that is sent to the client for transparency.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from app import field_bank
from app.jev_client import JevAnswer

#: Probability thresholds (same idea as jev2ui's `{expected, yes, destructive}`).
THRESHOLDS: dict[str, float] = {
    # Minimum probability of the top category; below it the item is "unsupported".
    "category_min": 0.40,
    # Plain yes/no decisions.
    "yes": 0.50,
    # Asking for an extra damage photo costs the user effort: be stricter.
    "damage": 0.60,
    # Expected plausibility level (0..3) under which details are sent back once.
    "plausible_min_level": 1.0,
    # Expected photo quality level (0..3) under which a retake hint is shown.
    "photo_quality_min_level": 1.5,
}

SUPPORTED_CATEGORIES = ("car", "motorcycle", "phone")
CATEGORY_OPTIONS = (*SUPPORTED_CATEGORIES, "unsupported")

PLAUSIBILITY_LEVELS = [
    "Contradictory: the details cannot all be true for this item",
    "Doubtful: at least one detail is unusual for this item",
    "Plausible: the details fit this item",
    "Fully consistent: every detail matches what is typical for this item",
]
CONDITION_LEVELS = ["Poor", "Fair", "Good", "Very good", "Like new"]
#: Price multiplier per condition level (index into CONDITION_LEVELS).
CONDITION_PRICE_FACTOR = [0.85, 0.93, 1.0, 1.03, 1.06]
PHOTO_QUALITY_LEVELS = [
    "Unusable: blurry, very dark, or the item is cut off",
    "Poor: the item is recognizable but details are hard to see",
    "Acceptable: the item is clear enough for a listing",
    "Good: sharp, well lit, the whole item is visible",
]


@dataclass(frozen=True)
class TraceEntry:
    """One decision as shown in the client's "Jev decisions" trace."""

    question: str
    kind: str
    answer: str
    probability: float
    outcome: str

    def to_dict(self) -> dict[str, Any]:
        return {**asdict(self), "probability": round(self.probability, 3)}


# ---------------------------------------------------------------------------
# Stage 1: the item photo
# ---------------------------------------------------------------------------


def photo_questions() -> dict[str, dict[str, Any]]:
    """Asked once, in parallel, about the initial item photo."""
    return {
        "category": {
            "type": "choice",
            "instructions": "Which kind of item is the main subject of the photo?",
            "criteria": {
                "car": "A passenger car, SUV, van, or pickup truck",
                "motorcycle": "A motorcycle, scooter, or motorbike",
                "phone": "A smartphone",
                "unsupported": "Anything else, or no single clear item",
            },
        },
        "is_ev": {
            "type": "noul",
            "instructions": (
                "The vehicle in the photo is battery-electric (for example: no exhaust "
                "pipe, EV badges, a charging port, or a closed front grille)."
            ),
        },
        "visible_damage": {
            "type": "noul",
            "instructions": (
                "The item in the photo shows visible damage such as dents, cracks, "
                "broken parts, or deep scratches."
            ),
        },
        "photo_quality": {
            "type": "score",
            "instructions": "How usable is this photo for a marketplace listing?",
            "criteria": PHOTO_QUALITY_LEVELS,
        },
        # One yes/no per candidate form field, in the same request: Jev decides
        # which questions are worth asking about *this* item.
        **{
            f"field_{spec.key}": {"type": "noul", "instructions": spec.when}
            for spec in field_bank.all_candidates()
        },
    }


@dataclass(frozen=True)
class PhotoDecision:
    category: str
    confidence: float
    is_ev: bool
    has_damage: bool
    retake_hint: bool
    trace: list[TraceEntry]


def decide_photo(answers: dict[str, JevAnswer]) -> PhotoDecision:
    cat = answers["category"]
    # Walk Jev's ranking to the first allowed option (jev2ui `make.ts` style).
    ranked = [c for c in cat.ranked() if c in CATEGORY_OPTIONS] or ["unsupported"]
    category = ranked[0]
    confidence = cat.probabilities.get(category, cat.probability)
    category_outcome = f"stage for '{category}'"
    if category != "unsupported" and confidence < THRESHOLDS["category_min"]:
        category_outcome = (
            f"'{category}' below {THRESHOLDS['category_min']:.0%} -> unsupported"
        )
        category = "unsupported"

    vehicle = category in ("car", "motorcycle")
    p_ev = answers["is_ev"].probability
    is_ev = vehicle and p_ev >= THRESHOLDS["yes"]
    p_damage = answers["visible_damage"].probability
    has_damage = category != "unsupported" and p_damage >= THRESHOLDS["damage"]
    quality = answers["photo_quality"]
    retake_hint = quality.expected_level < THRESHOLDS["photo_quality_min_level"]

    trace = [
        TraceEntry("category", "choice", ranked[0], confidence, category_outcome),
        TraceEntry(
            "is_ev",
            "noul",
            "yes" if p_ev >= THRESHOLDS["yes"] else "no",
            p_ev,
            ("battery fields" if is_ev else "engine fields") if vehicle else "n/a",
        ),
        TraceEntry(
            "visible_damage",
            "noul",
            "yes" if p_damage >= THRESHOLDS["damage"] else "no",
            p_damage,
            "damage box pre-checked" if has_damage else "damage box unchecked",
        ),
        TraceEntry(
            "photo_quality",
            "score",
            f"level {quality.expected_level:.1f}/3",
            quality.probability,
            "retake hint shown" if retake_hint else "photo accepted",
        ),
    ]
    return PhotoDecision(
        category, round(confidence, 2), is_ev, has_damage, retake_hint, trace
    )


@dataclass(frozen=True)
class FormDecision:
    #: Ordered `/details/<key>` fields of the step-1 form.
    fields: list[str]
    #: Short notices shown above the form.
    notices: list[str]
    trace: list[TraceEntry]


def decide_form(
    answers: dict[str, JevAnswer], photo: PhotoDecision
) -> FormDecision:
    """Builds the step-1 form for this photo from Jev's `field_<key>` answers.

    Base fields are always shown; each candidate needs `THRESHOLDS["yes"]`, and
    the strongest ones win when more than `MAX_EXTRA_FIELDS` qualify. When Jev
    sees damage, the damage question moves to the top with a notice.
    """
    scored = []
    trace = []
    for spec in field_bank.candidate_fields(photo.category, photo.is_ev):
        answer = answers.get(f"field_{spec.key}")
        p = answer.probability if answer else 0.0
        scored.append((p, spec.key))
    scored.sort(reverse=True)
    wanted = [k for p, k in scored if p >= THRESHOLDS["yes"]]
    shown = wanted[: field_bank.MAX_EXTRA_FIELDS]
    for p, key in scored:
        if key in shown:
            outcome = "field shown"
        elif key in wanted:
            outcome = f"skipped: only {field_bank.MAX_EXTRA_FIELDS} extra fields"
        else:
            outcome = "field skipped"
        trace.append(
            TraceEntry(
                f"field_{key}", "noul", "yes" if p >= THRESHOLDS["yes"] else "no", p, outcome
            )
        )
    fields = field_bank.assemble(
        photo.category, photo.is_ev, shown, damage_first=photo.has_damage
    )
    notices = (
        ["Jev sees possible damage in the photo. Tell buyers about it first."]
        if photo.has_damage
        else []
    )
    return FormDecision(fields, notices, trace)


# ---------------------------------------------------------------------------
# Stage 1 submit: the details the user typed
# ---------------------------------------------------------------------------


def details_questions(category: str) -> dict[str, dict[str, Any]]:
    questions: dict[str, dict[str, Any]] = {
        "plausible": {
            "type": "score",
            "instructions": (
                "How consistent are the listing details with each other and with the "
                "item they describe?"
            ),
            "criteria": PLAUSIBILITY_LEVELS,
        },
        "condition": {
            "type": "score",
            "instructions": "What is the overall condition of the item given these details?",
            "criteria": CONDITION_LEVELS,
        },
    }
    if category in ("car", "motorcycle"):
        questions["mileage_suspicious"] = {
            "type": "noul",
            "instructions": (
                "The reported mileage is implausible for the vehicle's age and type "
                "(for example far too low or far too high)."
            ),
        }
    return questions


@dataclass(frozen=True)
class DetailsDecision:
    send_back: bool
    want_odometer_photo: bool
    condition_level: int
    trace: list[TraceEntry]


def decide_details(
    answers: dict[str, JevAnswer], *, already_warned: bool, has_mileage: bool
) -> DetailsDecision:
    plausible = answers["plausible"]
    level = plausible.expected_level
    send_back = level < THRESHOLDS["plausible_min_level"] and not already_warned

    condition = answers["condition"]
    condition_level = max(
        0, min(len(CONDITION_LEVELS) - 1, round(condition.expected_level))
    )

    trace = [
        TraceEntry(
            "plausible",
            "score",
            f"level {level:.1f}/3",
            plausible.probability,
            "sent back to review" if send_back else "accepted",
        ),
        TraceEntry(
            "condition",
            "score",
            CONDITION_LEVELS[condition_level],
            condition.probability,
            f"price x{CONDITION_PRICE_FACTOR[condition_level]}",
        ),
    ]

    want_odometer = False
    if "mileage_suspicious" in answers:
        p = answers["mileage_suspicious"].probability
        # Only meaningful when a mileage was typed; a missing one is a code rule.
        want_odometer = has_mileage and p >= THRESHOLDS["yes"]
        trace.append(
            TraceEntry(
                "mileage_suspicious",
                "noul",
                "yes" if p >= THRESHOLDS["yes"] else "no",
                p,
                "odometer photo requested" if want_odometer else "mileage accepted",
            )
        )
    return DetailsDecision(send_back, want_odometer, condition_level, trace)


# ---------------------------------------------------------------------------
# Stage 2: the damage close-up
# ---------------------------------------------------------------------------


def damage_photo_questions() -> dict[str, dict[str, Any]]:
    return {
        "damage_documented": {
            "type": "noul",
            "instructions": "The photo clearly shows a close-up of damage on an item.",
        }
    }


def decide_damage_photo(answers: dict[str, JevAnswer]) -> tuple[bool, TraceEntry]:
    p = answers["damage_documented"].probability
    ok = p >= THRESHOLDS["yes"]
    return ok, TraceEntry(
        "damage_documented",
        "noul",
        "yes" if ok else "no",
        p,
        "photo accepted" if ok else "retake requested",
    )
