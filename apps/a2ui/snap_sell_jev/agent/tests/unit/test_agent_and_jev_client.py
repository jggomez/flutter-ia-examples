"""SnapSellJevAgent through a real ADK Runner, and the TypeSafe client wrapper."""

from __future__ import annotations

import json
from typing import Any

import pytest
import typesafe_sdk
from google.adk.runners import InMemoryRunner
from google.genai import types

from app.agent import (
    A2UI_ACTION_PREFIX,
    A2UI_MIME_TYPE,
    JEV_TRACE_MIME_TYPE,
    SnapSellJevAgent,
    parse_turn,
)
from app.flow import SellingFlow
from app.jev_client import (
    JEV_IMAGE_MAX_SIDE,
    JEV_IMAGE_MIN_SIDE,
    JevUnavailableError,
    TypeSafeJev,
    _normalize,
    fit_photo_for_jev,
)
from tests.unit.fakes import FakeJev, FakeWriter

PHOTO = b"\xff\xd8\xff\xe0fake-jpeg"


def test_parse_turn_reads_action_photo_and_url() -> None:
    action = {"name": "upload_followup_photo", "context": {"requestType": "damage"}}
    content = types.Content(
        role="user",
        parts=[
            types.Part.from_text(text=A2UI_ACTION_PREFIX + json.dumps(action)),
            types.Part.from_bytes(data=PHOTO, mime_type="image/jpeg"),
            types.Part.from_text(
                text="[Uploaded photo available at image_url: http://h/u.jpg]"
            ),
        ],
    )
    turn = parse_turn(content)
    assert turn.action == action
    assert turn.photo == PHOTO
    assert turn.image_url == "http://h/u.jpg"


@pytest.mark.asyncio
async def test_agent_yields_a2ui_blobs_trace_and_persists_state() -> None:
    agent = SnapSellJevAgent(
        name="snap_sell_agent", flow=SellingFlow(FakeJev(), FakeWriter())
    )
    runner = InMemoryRunner(agent=agent, app_name="app")
    session = await runner.session_service.create_session(app_name="app", user_id="u")
    message = types.Content(
        role="user",
        parts=[
            types.Part.from_text(text="Analyze this item."),
            types.Part.from_bytes(data=PHOTO, mime_type="image/jpeg"),
        ],
    )
    events = [
        e
        async for e in runner.run_async(
            user_id="u", session_id=session.id, new_message=message
        )
    ]
    assert len(events) == 1
    parts = events[0].content.parts
    mimes = [p.inline_data.mime_type for p in parts if p.inline_data]
    assert mimes == [A2UI_MIME_TYPE, JEV_TRACE_MIME_TYPE]
    surface = json.loads(parts[1].inline_data.data)
    assert surface["createSurface"]["surfaceId"] == "selling_step_1_detected"

    stored = await runner.session_service.get_session(
        app_name="app", user_id="u", session_id=session.id
    )
    assert stored.state["stage"] == "selling_step_1_detected"
    assert stored.state["jev_photo"]["category"] == "car"


def test_missing_api_key_raises_explicit_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("JEV_API_KEY", raising=False)
    monkeypatch.delenv("TYPESAFE_API_KEY", raising=False)
    with pytest.raises(JevUnavailableError, match="JEV_API_KEY"):
        TypeSafeJev()._get_client()


def test_normalize_sdk_answers() -> None:
    n = _normalize(typesafe_sdk.NoulAnswer(noul=0.7))
    assert (n.kind, n.probability) == ("noul", 0.7)
    c = _normalize(
        typesafe_sdk.ChoiceAnswer(
            choice="car", confidence=0.9, probabilities={"car": 0.9, "phone": 0.1}
        )
    )
    assert c.choice == "car" and c.ranked() == ["car", "phone"]
    s = _normalize(
        typesafe_sdk.ScoreAnswer(
            score=2.0,
            confidence=0.8,
            legend={0: "a", 1: "b", 2: "c"},
            probabilities={0: 0.0, 1: 0.2, 2: 0.8},
        )
    )
    assert s.expected_level == pytest.approx(1.8)


class _FakeSdkClient:
    def __init__(self) -> None:
        self.kwargs: dict[str, Any] = {}

    async def system_one(self, **kwargs: Any) -> Any:
        self.kwargs = kwargs

        from types import SimpleNamespace

        return SimpleNamespace(
            answers={"visible_damage": typesafe_sdk.NoulAnswer(noul=0.66)}
        )


@pytest.mark.asyncio
async def test_ask_attaches_photo_as_image_asset() -> None:
    jev = TypeSafeJev(api_key="test-key")
    fake = _FakeSdkClient()
    jev._client = fake
    answers = await jev.ask(
        {"task": "t"},
        {"visible_damage": {"type": "noul", "instructions": "x"}},
        photo=_jpeg(4000, 3000),
    )
    assert answers["visible_damage"].probability == 0.66
    assert isinstance(fake.kwargs["state"]["photo"], typesafe_sdk.Image)


def _jpeg(width: int, height: int) -> bytes:
    import io

    from PIL import Image

    out = io.BytesIO()
    Image.new("RGB", (width, height), "white").save(out, format="JPEG")
    return out.getvalue()


def _size(photo: bytes) -> tuple[int, int]:
    import io

    from PIL import Image

    with Image.open(io.BytesIO(photo)) as img:
        return img.size


@pytest.mark.parametrize(
    ("given", "expected"),
    [
        ((4000, 3000), (JEV_IMAGE_MAX_SIDE, 768)),  # phone photo: downscaled
        ((716, 1600), (458, JEV_IMAGE_MAX_SIDE)),  # tall screenshot: downscaled
        ((800, 600), (800, 600)),  # already fits: unchanged
        ((256, 256), (JEV_IMAGE_MIN_SIDE, JEV_IMAGE_MIN_SIDE)),  # too small: upscaled
    ],
)
def test_fit_photo_for_jev_keeps_sides_in_accepted_range(
    given: tuple[int, int], expected: tuple[int, int]
) -> None:
    assert _size(fit_photo_for_jev(_jpeg(*given))) == expected


def test_client_sends_the_image_opt_in_header() -> None:
    client = TypeSafeJev(api_key="test-key")._get_client()
    # Without this header the API answers 400 "Images are experimental".
    assert client._config.default_headers["TypeSafe-Danger-Zone-Images"] == "true"


@pytest.mark.asyncio
async def test_ask_fails_when_a_question_is_unanswered() -> None:
    jev = TypeSafeJev(api_key="test-key")
    jev._client = _FakeSdkClient()
    with pytest.raises(JevUnavailableError, match="did not answer"):
        await jev.ask({}, {"visible_damage": {}, "is_ev": {}})
