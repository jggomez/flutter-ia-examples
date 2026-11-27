"""Unit tests for A2A <-> A2UI v1.0 part converters, the agent-function executor and AgentCard capabilities."""

from __future__ import annotations

from typing import Any

import pytest
from google.adk.a2a import _compat
from google.genai import types as genai_types

from app.app_utils.a2a import (
    A2UI_EXTENSION_URI,
    A2UI_MIME_TYPE,
    SnapSellA2uiExecutor,
    _default_capabilities,
    convert_snap_sell_a2a_part_to_genai,
    convert_snap_sell_genai_part_to_a2a,
)
from app.catalog import SNAP_SELL_CATALOG_ID

EXPRESS_REPLY = """I detected an unsupported item.
<a2ui>
surface("selling_unsupported")
root = Card(col)
col = Column([warn, btn])
warn = Icon("warning")
btn = Button(lbl, "primary", Event("start_new_listing", {}))
lbl = Text("Try another photo")
</a2ui>"""


def test_default_capabilities_advertises_a2ui_v1_extension() -> None:
    caps = _default_capabilities()
    assert caps.streaming is True
    assert A2UI_EXTENSION_URI.endswith("/v1.0")
    a2ui_exts = [e for e in caps.extensions if e.uri == A2UI_EXTENSION_URI]
    assert len(a2ui_exts) == 1
    params = _compat.meta_to_dict(a2ui_exts[0].params) or dict(
        a2ui_exts[0].params or {}
    )
    assert params.get("supportedCatalogIds") == [SNAP_SELL_CATALOG_ID]


def test_convert_v1_action_datapart_to_genai_text() -> None:
    payload = {
        "version": "1.0",
        "action": {
            "name": "submit_detected_details",
            "surfaceId": "selling_step_1_detected",
            "sourceComponentId": "continue_btn",
            "timestamp": "2026-11-21T10:00:00Z",
            "userMessage": "Continue",
            "context": {"brand": "Mazda", "mileageKm": "34200"},
        },
    }
    part = _compat.make_data_part(data=payload, metadata={"mimeType": A2UI_MIME_TYPE})
    converted = convert_snap_sell_a2a_part_to_genai(part)
    assert isinstance(converted, genai_types.Part)
    assert converted.text is not None
    assert "submit_detected_details" in converted.text
    assert "selling_step_1_detected" in converted.text
    assert "user said: Continue" in converted.text
    assert "Mazda" in converted.text


def test_convert_v1_error_datapart_asks_for_corrected_surface() -> None:
    payload = {
        "version": "1.0",
        "error": {"code": "UNALLOWED_PARENT", "message": "bad", "surfaceId": "s"},
    }
    converted = convert_snap_sell_a2a_part_to_genai(
        _compat.make_data_part(data=payload)
    )
    assert isinstance(converted, genai_types.Part)
    assert "UNALLOWED_PARENT" in (converted.text or "")


def test_convert_a2a_image_filepart_saves_upload_and_appends_url() -> None:
    fake_jpeg = (
        b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
    )
    file_part = _compat.make_file_part_with_bytes(
        data=fake_jpeg, mime_type="image/jpeg", name="car.jpg"
    )
    converted = convert_snap_sell_a2a_part_to_genai(file_part)
    assert isinstance(converted, list)
    assert len(converted) == 2
    assert converted[0].inline_data is not None
    assert converted[0].inline_data.data == fake_jpeg
    assert "[Uploaded photo available at image_url:" in (converted[1].text or "")


def test_convert_express_text_to_v1_dataparts() -> None:
    a2a_parts = convert_snap_sell_genai_part_to_a2a(
        genai_types.Part.from_text(text=EXPRESS_REPLY)
    )
    assert isinstance(a2a_parts, list)
    text_parts = [p for p in a2a_parts if _compat.is_text_part(p)]
    data_parts = [p for p in a2a_parts if _compat.is_data_part(p)]
    assert len(text_parts) == 1
    assert "unsupported item" in _compat.part_text(text_parts[0])
    assert len(data_parts) == 1
    assert (
        _compat.part_metadata(data_parts[0]).get("mimeType") == "application/a2ui+json"
    )
    message = _compat.data_part_dict(data_parts[0])
    assert message["version"] == "1.0"
    assert message["createSurface"]["surfaceId"] == "selling_unsupported"


def test_invalid_express_never_reaches_the_renderer() -> None:
    reply = 'Here you go.\n<a2ui>\nsurface("x")\nroot = NotAComponent(1)\n</a2ui>'
    converted = convert_snap_sell_genai_part_to_a2a(
        genai_types.Part.from_text(text=reply)
    )
    assert converted is not None
    assert not isinstance(converted, list)
    assert _compat.part_text(converted) == "Here you go."


class _Queue:
    def __init__(self) -> None:
        self.events: list[Any] = []

    async def enqueue_event(self, event: Any) -> None:
        self.events.append(event)


class _Inner:
    def __init__(self) -> None:
        self.called = False

    async def execute(self, context: Any, event_queue: Any) -> None:
        self.called = True

    async def cancel(self, context: Any, event_queue: Any) -> None:
        pass


class _Context:
    def __init__(self, parts: list[Any]) -> None:
        self.message = _compat.make_message(message_id="m1", role="user", parts=parts)
        self.context_id = "ctx-1"


def _price_call(asking: float) -> dict[str, Any]:
    return {
        "version": "1.0",
        "callAgentFunction": {
            "surfaceId": "selling_step_3_preview",
            "functionCallId": "call_1",
            "callFunction": {
                "@call": "priceFeedback",
                "catalogId": SNAP_SELL_CATALOG_ID,
                "args": {
                    "askingPrice": asking,
                    "minPrice": 21500,
                    "suggestedPrice": 23400,
                    "maxPrice": 24900,
                },
            },
        },
    }


@pytest.mark.asyncio
async def test_executor_answers_call_agent_function_without_llm() -> None:
    inner, queue = _Inner(), _Queue()
    executor = SnapSellA2uiExecutor(inner)  # type: ignore[arg-type]
    context = _Context([_compat.make_data_part(data=_price_call(23400))])
    await executor.execute(context, queue)  # type: ignore[arg-type]

    assert inner.called is False
    assert len(queue.events) == 1
    reply = _compat.data_part_dict(queue.events[0].parts[0])
    assert reply["version"] == "1.0"
    assert reply["agentFunctionResponse"]["functionCallId"] == "call_1"
    assert "competitive" in reply["agentFunctionResponse"]["value"]


@pytest.mark.asyncio
async def test_executor_delegates_other_messages_to_adk() -> None:
    inner, queue = _Inner(), _Queue()
    executor = SnapSellA2uiExecutor(inner)  # type: ignore[arg-type]
    await executor.execute(_Context([_compat.make_text_part("hi")]), queue)  # type: ignore[arg-type]
    assert inner.called is True
    assert queue.events == []
