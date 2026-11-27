"""Offline stand-ins for Jev and Gemini: scripted answers, recorded calls."""

from __future__ import annotations

from typing import Any

from app.jev_client import JevAnswer, JevUnavailableError
from app.writer import ItemAttributes, ListingCopy, OdometerReading


def noul(p: float) -> JevAnswer:
    return JevAnswer(kind="noul", probability=p)


def choice(probabilities: dict[str, float]) -> JevAnswer:
    best = max(probabilities, key=probabilities.__getitem__)
    return JevAnswer(
        kind="choice",
        probability=probabilities[best],
        choice=best,
        probabilities=probabilities,
    )


def score(levels: list[float]) -> JevAnswer:
    """`levels[i]` is the probability of criterion i."""
    return JevAnswer(
        kind="score",
        probability=max(levels),
        probabilities={str(i): p for i, p in enumerate(levels)},
    )


def level(index: int, size: int) -> JevAnswer:
    """A score answer that is certain about one level."""
    return score([1.0 if i == index else 0.0 for i in range(size)])


DEFAULT_ANSWERS: dict[str, JevAnswer] = {
    "category": choice(
        {"car": 0.94, "motorcycle": 0.03, "phone": 0.01, "unsupported": 0.02}
    ),
    "is_ev": noul(0.08),
    "visible_damage": noul(0.1),
    "photo_quality": level(3, 4),
    "plausible": level(3, 4),
    "condition": level(2, 5),
    "mileage_suspicious": noul(0.1),
    "damage_documented": noul(0.9),
}


class FakeJev:
    def __init__(self, **overrides: JevAnswer) -> None:
        self.answers = {**DEFAULT_ANSWERS, **overrides}
        self.calls: list[dict[str, Any]] = []
        self.fail = False

    async def ask(
        self,
        state: dict[str, Any],
        questions: dict[str, dict[str, Any]],
        *,
        photo: bytes | None = None,
    ) -> dict[str, JevAnswer]:
        self.calls.append({"state": state, "questions": questions, "photo": photo})
        if self.fail:
            raise JevUnavailableError("JEV_API_KEY is not set.")
        # Form-field questions default to "not worth asking" unless a test overrides them.
        return {
            name: self.answers.get(name, noul(0.2))
            if name.startswith("field_")
            else self.answers[name]
            for name in questions
        }


class FakeWriter:
    def __init__(self) -> None:
        self.attributes = ItemAttributes(
            brand="Mazda",
            model="CX-30",
            year="2021",
            color="Soul Red",
            summary="Clean SUV.",
        )
        self.odometer = OdometerReading(raw_reading_text="034,200", unit="km")
        self.fail_copy = False
        self.listing_facts: dict[str, Any] | None = None

    async def describe_item(self, photo: bytes) -> ItemAttributes:
        return self.attributes

    async def read_odometer(self, photo: bytes) -> OdometerReading:
        return self.odometer

    async def write_listing(self, facts: dict[str, Any]) -> ListingCopy:
        self.listing_facts = facts
        if self.fail_copy:
            raise RuntimeError("Gemini unavailable")
        return ListingCopy(
            title="2021 Mazda CX-30", description="Clean SUV.", rationale="Fair range."
        )
