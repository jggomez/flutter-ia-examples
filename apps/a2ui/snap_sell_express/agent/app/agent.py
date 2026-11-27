# ruff: noqa
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import logging
import os
import uuid

from a2ui.core import A2uiError
from google.adk.agents import Agent
from google.adk.agents.callback_context import CallbackContext
from google.adk.agents.readonly_context import ReadonlyContext
from google.adk.apps import App
from google.adk.models import Gemini
from google.adk.models.llm_request import LlmRequest
from google.adk.models.llm_response import LlmResponse
from google.adk.tools import FunctionTool
from google.adk.utils.content_utils import SKIP_THOUGHT_SIGNATURE_VALIDATOR
from google.genai import types

from app.catalog import build_a2ui_system_instructions, get_a2ui_processor
from app.tools import (
    estimate_price_and_build_preview,
    extract_odometer_reading,
    record_detected_item,
    validate_listing_fields,
)

logger = logging.getLogger(__name__)

MODEL = os.getenv("AGENT_MODEL", "gemini-3.8-flash")
THINKING_LEVEL = os.getenv("THINKING_LEVEL", "low")
A2UI_EXPRESS_OPEN_TAG = "<a2ui>"
MAX_A2UI_REPAIRS = 1
_RETRIES_STATE_KEY = "temp:a2ui_repairs"
_REPAIR_TOOL_NAME = "a2ui_report_compile_error"


_SYSTEM_INSTRUCTIONS = build_a2ui_system_instructions()


def system_instructions(context: ReadonlyContext) -> str:
    """InstructionProvider: returns the prompt verbatim.

    A callable instruction skips ADK's `{state_key}` templating, which would
    otherwise try to interpolate the braces of the Express examples.
    """
    del context
    return _SYSTEM_INSTRUCTIONS


def initialize_selling_session(callback_context: CallbackContext) -> None:
    """Initializes default session state keys before each agent invocation."""
    callback_context.state.setdefault("listing_draft", {})
    callback_context.state.setdefault("stage", "entry")
    callback_context.state[_RETRIES_STATE_KEY] = 0


def a2ui_report_compile_error(error_details: str, retry_count: int) -> dict[str, str]:
    """Framework-only tool that returns repair guidance for a rejected A2UI Express block. Never call it directly."""
    return {
        "reflection_guidance": (
            f"Your previous <a2ui> block was rejected by the A2UI v1.0 compiler "
            f"(repair attempt {retry_count} of {MAX_A2UI_REPAIRS}).\n"
            f"Compiler error: {error_details}\n"
            "Rewrite the WHOLE reply with a corrected <a2ui> block that follows the "
            "catalog signatures and composition rules. Do not repeat the same mistake."
        )
    }


def provide_a2ui_repair_tool(
    callback_context: CallbackContext, llm_request: LlmRequest
) -> None:
    """Registers the repair tool for execution only (it is not advertised to the model)."""
    del callback_context
    llm_request.tools_dict[_REPAIR_TOOL_NAME] = FunctionTool(
        func=a2ui_report_compile_error
    )


def validate_a2ui_model_output(
    callback_context: CallbackContext,
    llm_response: LlmResponse,
) -> LlmResponse | None:
    """Compiles the Express block of a final reply and asks the model to repair it once if invalid.

    Same mechanism as ADK's ReflectAndRetryModelPlugin: the invalid reply is
    replaced by a synthetic call to a framework tool whose response carries the
    compiler error, so ADK re-invokes the model with that guidance.
    """
    if (
        llm_response.partial
        or not llm_response.content
        or not llm_response.content.parts
    ):
        return None
    text = "".join(part.text or "" for part in llm_response.content.parts)
    if A2UI_EXPRESS_OPEN_TAG not in text:
        return None
    try:
        get_a2ui_processor().parse_response(text, wrapped=True)
        return None
    except A2uiError as exc:
        repairs = int(callback_context.state.get(_RETRIES_STATE_KEY, 0)) + 1
        if repairs > MAX_A2UI_REPAIRS:
            logger.warning("A2UI Express block still invalid after repair: %s", exc)
            return None
        callback_context.state[_RETRIES_STATE_KEY] = repairs
        logger.info("A2UI Express block rejected, asking the model to repair: %s", exc)
        return LlmResponse(
            content=types.Content(
                role="model",
                parts=[
                    types.Part(
                        function_call=types.FunctionCall(
                            id=f"a2ui-repair-{uuid.uuid4().hex[:8]}",
                            name=_REPAIR_TOOL_NAME,
                            args={"error_details": str(exc), "retry_count": repairs},
                        ),
                        thought_signature=SKIP_THOUGHT_SIGNATURE_VALIDATOR,
                    )
                ],
            )
        )


root_agent = Agent(
    name="snap_sell_agent",
    model=Gemini(
        model=MODEL,
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    description=(
        "Multimodal Snap & Sell marketplace assistant that inspects item photos "
        "and generates dynamic A2UI v1.0 selling surfaces with A2UI Express."
    ),
    instruction=system_instructions,
    # The agent fills a known screen template, so deep reasoning only adds latency.
    generate_content_config=types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_level=THINKING_LEVEL)
    ),
    tools=[
        record_detected_item,
        validate_listing_fields,
        extract_odometer_reading,
        estimate_price_and_build_preview,
    ],
    before_agent_callback=initialize_selling_session,
    before_model_callback=provide_a2ui_repair_tool,
    after_model_callback=validate_a2ui_model_output,
)

app = App(
    root_agent=root_agent,
    name="app",
)
