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

"""Snap & Sell (Jev variant): a deterministic ADK agent, no LLM writing UI.

`SnapSellJevAgent` is a custom `BaseAgent`. Each turn it parses the user's
content (an A2UI action and/or a photo), runs `SellingFlow` and yields one
event whose parts are: prose, one inline blob per A2UI v1.0 message, and the
Jev decision trace. `app.app_utils.a2a` turns those blobs into A2A DataParts.
"""

from __future__ import annotations

import json
import logging
import re
from collections.abc import AsyncGenerator
from typing import Any

from google.adk.agents import BaseAgent
from google.adk.agents.invocation_context import InvocationContext
from google.adk.apps import App
from google.adk.events import Event, EventActions
from google.genai import types
from pydantic import ConfigDict

from app.flow import SellingFlow, TurnInput, TurnOutput

logger = logging.getLogger(__name__)

#: Prefix of the text part the A2A converter makes from an A2UI `action`.
A2UI_ACTION_PREFIX = "A2UI_ACTION "
A2UI_MIME_TYPE = "application/a2ui+json"
#: Not an A2UI message: the client shows it in its "Jev decisions" panel.
JEV_TRACE_MIME_TYPE = "application/vnd.snap-sell.jev-trace+json"
_UPLOADED_URL_RE = re.compile(r"\[Uploaded photo available at image_url: (\S+)\]")


def parse_turn(content: types.Content | None) -> TurnInput:
    """Extracts the action, the photo bytes and its public URL from the user turn."""
    turn = TurnInput()
    for part in (content.parts or []) if content else []:
        if part.text:
            if part.text.startswith(A2UI_ACTION_PREFIX):
                turn.action = json.loads(part.text[len(A2UI_ACTION_PREFIX) :])
            elif match := _UPLOADED_URL_RE.search(part.text):
                turn.image_url = match.group(1)
        elif part.inline_data and part.inline_data.data:
            mime = (part.inline_data.mime_type or "").lower()
            if mime.startswith("image/") or not mime.startswith("text/"):
                turn.photo = part.inline_data.data
    return turn


def output_parts(out: TurnOutput) -> list[types.Part]:
    parts: list[types.Part] = []
    if out.text:
        parts.append(types.Part.from_text(text=out.text))
    for message in out.messages:
        parts.append(
            types.Part.from_bytes(
                data=json.dumps(message, ensure_ascii=False).encode(),
                mime_type=A2UI_MIME_TYPE,
            )
        )
    if out.trace:
        parts.append(
            types.Part.from_bytes(
                data=json.dumps({"jevTrace": out.trace}).encode(),
                mime_type=JEV_TRACE_MIME_TYPE,
            )
        )
    return parts


def _default_flow() -> SellingFlow:
    from app.jev_client import TypeSafeJev
    from app.writer import GeminiWriter

    return SellingFlow(jev=TypeSafeJev(), writer=GeminiWriter())


class SnapSellJevAgent(BaseAgent):
    """Runs one wizard step per turn: Jev decides, Gemini writes, code assembles."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    flow: Any = None

    async def _run_async_impl(
        self, ctx: InvocationContext
    ) -> AsyncGenerator[Event, None]:
        if self.flow is None:
            self.flow = _default_flow()
        turn = parse_turn(ctx.user_content)
        out: TurnOutput = await self.flow.handle(dict(ctx.session.state), turn)
        for entry in out.trace:
            logger.info("jev %s", entry)
        yield Event(
            author=self.name,
            invocation_id=ctx.invocation_id,
            branch=ctx.branch,
            content=types.Content(role="model", parts=output_parts(out)),
            actions=EventActions(state_delta=out.state),
        )


root_agent = SnapSellJevAgent(
    name="snap_sell_agent",
    description=(
        "Snap & Sell marketplace assistant where Jev (TypeSafe) makes every UI "
        "decision, Gemini writes copy, and code assembles A2UI v1.0 surfaces."
    ),
)

app = App(root_agent=root_agent, name="app")
