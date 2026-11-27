"""Unit tests for the price_feedback agent function and the A2UI Express repair callback."""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from google.adk.models.llm_response import LlmResponse
from google.genai import types

from app.agent import (
    MAX_A2UI_REPAIRS,
    a2ui_report_compile_error,
    validate_a2ui_model_output,
)
from app.tools import price_feedback

BAND = {"minPrice": 100.0, "suggestedPrice": 150.0, "maxPrice": 200.0}


def test_price_feedback_labels() -> None:
    assert "Below market" in price_feedback({"askingPrice": 90.0, **BAND})
    assert "Above market" in price_feedback({"askingPrice": 250.0, **BAND})
    assert "competitive" in price_feedback({"askingPrice": 152.0, **BAND})
    assert "below suggested" in price_feedback({"askingPrice": 120.0, **BAND})
    assert "above suggested" in price_feedback({"askingPrice": 180.0, **BAND})


def _ctx() -> Any:
    return SimpleNamespace(state={})


def _reply(text: str) -> LlmResponse:
    return LlmResponse(
        content=types.Content(role="model", parts=[types.Part(text=text)])
    )


def test_valid_express_reply_is_left_untouched() -> None:
    reply = '<a2ui>\nsurface("selling_unsupported")\nroot = Card(i)\ni = Icon("warning")\n</a2ui>'
    assert validate_a2ui_model_output(_ctx(), _reply(reply)) is None


def test_invalid_express_reply_becomes_one_repair_call() -> None:
    ctx = _ctx()
    bad = _reply('<a2ui>\nsurface("x")\nroot = Missing(1)\n</a2ui>')

    repair = validate_a2ui_model_output(ctx, bad)
    assert repair is not None
    call = repair.content.parts[0].function_call
    assert call.name == "a2ui_report_compile_error"
    assert call.args["retry_count"] == 1

    # Past MAX_A2UI_REPAIRS the reply is passed through (the converter drops the block).
    for _ in range(MAX_A2UI_REPAIRS):
        validate_a2ui_model_output(ctx, bad)
    assert validate_a2ui_model_output(ctx, bad) is None


def test_repair_tool_returns_compiler_error_guidance() -> None:
    guidance = a2ui_report_compile_error("Unknown component 'Missing'", 1)
    assert "Unknown component 'Missing'" in guidance["reflection_guidance"]
