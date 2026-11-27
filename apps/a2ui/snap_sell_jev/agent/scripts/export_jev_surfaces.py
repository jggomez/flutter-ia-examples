"""Writes the surfaces app.surfaces assembles to contracts/examples/jev/.

The Flutter suite renders these files (test/catalog/jev_surfaces_render_test.dart)
to prove the code-assembled trees work in the real renderer, not only in the
Python validator. Run: `uv run python scripts/export_jev_surfaces.py`.
"""

# demo-data: approved — dev tool: runs the flow with the test stand-ins to write contracts/examples/jev fixtures; never used by the app.

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AGENT_DIR))

from app.flow import SellingFlow, TurnInput  # noqa: E402
from tests.unit.fakes import FakeJev, FakeWriter, choice, noul  # noqa: E402

OUT_DIR = AGENT_DIR.parent / "contracts" / "examples" / "jev"
PHOTO = b"\xff\xd8\xff\xe0demo"
URL = "http://10.0.2.2:8000/uploads/demo_item.jpg"
CAR = {
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
    "hasDamage": True,
}


def _action(name: str, **ctx: object) -> TurnInput:
    return TurnInput(action={"name": name, "surfaceId": "s", "context": ctx})


async def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files: dict[str, list] = {}
    # Each photo gets its own form: Jev's `field_<key>` answers pick the extra fields.
    flow = SellingFlow(
        FakeJev(
            field_ownersCount=noul(0.8),
            field_serviceHistory=noul(0.75),
            field_tiresCondition=noul(0.6),
        ),
        FakeWriter(),
    )
    car = await flow.handle({}, TurnInput(photo=PHOTO, image_url=URL))
    files["01_detected_car.json"] = car.messages
    ev = await SellingFlow(
        FakeJev(
            is_ev=noul(0.9),
            field_batteryHealthPct=noul(0.85),
            field_warrantyActive=noul(0.8),
        ),
        FakeWriter(),
    ).handle({}, TurnInput(photo=PHOTO, image_url=URL))
    files["02_detected_ev.json"] = ev.messages
    phone = await SellingFlow(
        FakeJev(
            category=choice({"phone": 0.96, "car": 0.04}),
            visible_damage=noul(0.9),
            field_screenCondition=noul(0.95),
            field_biometricsWork=noul(0.7),
            field_batteryHealthPct=noul(0.6),
        ),
        FakeWriter(),
    ).handle({}, TurnInput(photo=PHOTO, image_url=URL))
    files["03_detected_phone.json"] = phone.messages
    classic = await SellingFlow(
        FakeJev(
            field_originalParts=noul(0.9),
            field_restoration=noul(0.85),
            field_papersUpToDate=noul(0.7),
        ),
        FakeWriter(),
    ).handle({}, TurnInput(photo=PHOTO, image_url=URL))
    files["08_detected_classic_car.json"] = classic.messages
    moto = await SellingFlow(
        FakeJev(
            category=choice({"motorcycle": 0.93, "car": 0.07}),
            field_modifications=noul(0.85),
            field_chainCondition=noul(0.8),
            field_includesHelmet=noul(0.6),
        ),
        FakeWriter(),
    ).handle({}, TurnInput(photo=PHOTO, image_url=URL))
    files["09_detected_sport_motorcycle.json"] = moto.messages
    follow = await flow.handle(car.state, _action("submit_detected_details", **CAR))
    files["04_followup_damage.json"] = follow.messages
    preview = await flow.handle(
        {**follow.state, "need_damage": False}, _action("submit_followup")
    )
    files["05_listing_preview.json"] = preview.messages
    files["06_published.json"] = (
        await flow.handle(
            {},
            _action(
                "publish_listing",
                title="2021 Mazda CX-30",
                askingPrice=23400,
                currency="USD",
            ),
        )
    ).messages
    files["07_unsupported.json"] = (
        await SellingFlow(
            FakeJev(category=choice({"unsupported": 0.9, "car": 0.1})), FakeWriter()
        ).handle({}, TurnInput(photo=PHOTO))
    ).messages
    for name, messages in files.items():
        assert messages, name
        (OUT_DIR / name).write_text(
            json.dumps(messages, indent=2, ensure_ascii=False) + "\n"
        )
    print(f"wrote {len(files)} surfaces to {OUT_DIR}")


if __name__ == "__main__":
    asyncio.run(main())
