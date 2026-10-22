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

from a2ui.core import A2uiError
from google.adk.agents import Agent
from google.adk.agents.callback_context import CallbackContext
from google.adk.apps import App
from google.adk.models import Gemini
from google.adk.models.llm_response import LlmResponse
from google.genai import types

from app.catalog import build_a2ui_system_instructions, get_a2ui_processor
from app.tools import (
    estimate_price_and_build_preview,
    extract_odometer_reading,
    record_detected_item,
    validate_listing_fields,
)

logger = logging.getLogger(__name__)

MODEL = "gemini-3.8-flash"


def initialize_selling_session(callback_context: CallbackContext) -> None:
    """Initializes default session state keys before each agent invocation."""
    callback_context.state.setdefault("listing_draft", {})
    callback_context.state.setdefault("stage", "entry")


def validate_a2ui_model_output(
    callback_context: CallbackContext,
    llm_response: LlmResponse,
) -> LlmResponse | None:
    """Validates <a2ui-json> blocks in final model responses against the Snap & Sell catalog."""
    del callback_context
    if not llm_response.content or not llm_response.content.parts:
        return None

    for part in llm_response.content.parts:
        if part.text and "<a2ui-json>" in part.text:
            try:
                get_a2ui_processor().parse_response(part.text, wrapped=True)
            except A2uiError as exc:
                logger.warning("A2UI validation warning on model output: %s", exc)
    return None


root_agent = Agent(
    name="snap_sell_agent",
    model=Gemini(
        model=MODEL,
        retry_options=types.HttpRetryOptions(attempts=3),
    ),
    description=(
        "Multimodal Snap & Sell marketplace assistant that inspects item photos "
        "and generates dynamic A2UI v0.9 selling surfaces."
    ),
    instruction=build_a2ui_system_instructions(),
    tools=[
        record_detected_item,
        validate_listing_fields,
        extract_odometer_reading,
        estimate_price_and_build_preview,
    ],
    before_agent_callback=initialize_selling_session,
    after_model_callback=validate_a2ui_model_output,
)

app = App(
    root_agent=root_agent,
    name="app",
)
