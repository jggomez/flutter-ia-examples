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

"""A2A (Agent2Agent) endpoints and A2UI v1.0 part converters for the FastAPI app.

Agent -> renderer: `SnapSellJevAgent` yields each A2UI v1.0 message as an
inline blob (`application/a2ui+json`); it becomes one A2A DataPart. The Jev
decision trace travels the same way under its own MIME type.

Renderer -> agent: an `action` becomes a machine-readable text part
(`A2UI_ACTION {json}`) that `app.agent.parse_turn` reads back; `error`
messages are logged. `callAgentFunction` messages are answered by
`SnapSellA2uiExecutor` directly (an `agentFunctionResponse`).
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Any

from a2a import types as a2a_types
from a2a.server.agent_execution import AgentExecutor, RequestContext
from a2a.server.events import EventQueue
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.routes import (
    add_a2a_routes_to_fastapi,
    create_agent_card_routes,
    create_jsonrpc_routes,
)
from a2a.server.tasks import TaskStore
from a2a.types import AgentCapabilities, AgentCard, AgentExtension, AgentInterface
from a2a.utils.constants import AGENT_CARD_WELL_KNOWN_PATH
from a2ui.core import A2uiError
from a2ui.rpc import RendererToAgentMessageProcessor
from google.adk.a2a import _compat
from google.adk.a2a.converters.part_converter import (
    convert_a2a_part_to_genai_part,
    convert_genai_part_to_a2a_part,
)
from google.adk.a2a.executor.a2a_agent_executor import A2aAgentExecutor
from google.adk.a2a.executor.config import A2aAgentExecutorConfig
from google.adk.a2a.utils.agent_card_builder import AgentCardBuilder
from google.genai import types as genai_types

from app.agent import A2UI_ACTION_PREFIX, JEV_TRACE_MIME_TYPE
from app.catalog import (
    SNAP_SELL_CATALOG_ID,
    get_a2ui_generator,
    get_a2ui_processor,
    renderer_capabilities_from_metadata,
)

if TYPE_CHECKING:
    from fastapi import FastAPI
    from google.adk.agents import BaseAgent
    from google.adk.runners import Runner

logger = logging.getLogger(__name__)

_ADK_AGENT_EXECUTOR_EXTENSION_URI = (
    "https://google.github.io/adk-docs/a2a/a2a-extension/"
)
A2UI_EXTENSION_URI = "https://a2ui.org/a2a-extension/a2ui/v1.0"
#: v1.0 renamed the MIME type (v0.9 used `application/json+a2ui`).
A2UI_MIME_TYPE = "application/a2ui+json"
UPLOAD_DIR = Path(os.getenv("SNAP_SELL_UPLOAD_DIR", "/tmp/snap_sell_uploads"))


def _add_v0_3_compat_interface(card: AgentCard) -> AgentCard:
    """Advertise a v0.3 JSON-RPC interface so the served card stays consumable by v0.3 A2A clients."""
    if card.supported_interfaces and not any(
        i.protocol_binding == "JSONRPC" and i.protocol_version == "0.3"
        for i in card.supported_interfaces
    ):
        card.supported_interfaces.append(
            AgentInterface(
                protocol_binding="JSONRPC",
                protocol_version="0.3",
                url=card.supported_interfaces[0].url,
            )
        )
    return card


def _default_capabilities() -> AgentCapabilities:
    """Returns the default A2A capabilities advertising A2UI v1.0 support."""
    return AgentCapabilities(
        streaming=True,
        extensions=[
            AgentExtension(
                uri=A2UI_EXTENSION_URI,
                description=(
                    "Supports A2UI v1.0 dynamic surfaces (generated with A2UI Express) "
                    "and agent functions for Snap & Sell"
                ),
                required=False,
                params={"supportedCatalogIds": [SNAP_SELL_CATALOG_ID]},
            ),
            AgentExtension(
                uri=_ADK_AGENT_EXECUTOR_EXTENSION_URI,
                description="Ability to use the new agent executor implementation",
            ),
        ],
    )


def _data_part_payload(part: a2a_types.Part) -> dict[str, Any] | None:
    """Returns the JSON object carried by an A2A DataPart, if any."""
    if _compat.is_data_part(part):
        data = _compat.data_part_dict(part)
        if isinstance(data, dict):
            return data
    root = getattr(part, "root", part)
    raw_data = getattr(root, "data", None)
    return raw_data if isinstance(raw_data, dict) else None


def _a2ui_renderer_message(part: a2a_types.Part, kind: str) -> dict[str, Any] | None:
    """Returns the body of a renderer -> agent message of `kind` carried by `part`."""
    payload = _data_part_payload(part)
    if payload is None:
        return None
    body = payload.get(kind)
    return dict(body) if isinstance(body, dict) else None


def convert_snap_sell_a2a_part_to_genai(
    part: a2a_types.Part,
) -> genai_types.Part | list[genai_types.Part] | None:
    """Converts incoming A2A parts (A2UI v1.0 actions/errors and uploaded photos) into GenAI parts."""
    action = _a2ui_renderer_message(part, "action")
    if action is not None:
        return genai_types.Part.from_text(
            text=A2UI_ACTION_PREFIX + json.dumps(action, ensure_ascii=False)
        )

    error = _a2ui_renderer_message(part, "error")
    if error is not None:
        # Surfaces are assembled by code and validated before sending, so a
        # renderer error is a bug to fix, not something to retry with a model.
        logger.error("A2UI renderer rejected a surface: %s", error)
        return None

    if _a2ui_renderer_message(part, "callAgentFunction") is not None:
        # Answered by SnapSellA2uiExecutor; never part of an LLM turn.
        return None

    converted = convert_a2a_part_to_genai_part(part)
    if (
        converted is not None
        and converted.inline_data is not None
        and converted.inline_data.data
    ):
        mime = (converted.inline_data.mime_type or "").lower()
        if mime.startswith("image/") or not mime.startswith("text/"):
            UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
            filename = f"{uuid.uuid4().hex}.jpg"
            target_path = UPLOAD_DIR / filename
            target_path.write_bytes(converted.inline_data.data)
            base_url = os.getenv("PUBLIC_BASE_URL", "http://10.0.2.2:8000").rstrip("/")
            public_url = f"{base_url}/uploads/{filename}"
            return [
                converted,
                genai_types.Part.from_text(
                    text=f"[Uploaded photo available at image_url: {public_url}]"
                ),
            ]

    return converted


def _a2ui_data_part(message: dict[str, Any]) -> a2a_types.Part:
    return _compat.make_data_part(data=message, metadata={"mimeType": A2UI_MIME_TYPE})


def convert_snap_sell_genai_part_to_a2a(
    part: genai_types.Part,
) -> a2a_types.Part | list[a2a_types.Part] | None:
    """Turns the agent's A2UI / Jev-trace blobs into A2A DataParts."""
    blob = part.inline_data
    if (
        blob is not None
        and blob.data
        and blob.mime_type
        in (
            A2UI_MIME_TYPE,
            JEV_TRACE_MIME_TYPE,
        )
    ):
        return _compat.make_data_part(
            data=json.loads(blob.data), metadata={"mimeType": blob.mime_type}
        )
    return convert_genai_part_to_a2a_part(part)


class SnapSellA2uiExecutor(AgentExecutor):
    """Answers A2UI `callAgentFunction` requests in place; everything else goes to ADK.

    A v1.0 renderer calls an agent function (here `priceFeedback`) whenever a
    bound value changes. Those calls must be fast and deterministic, so they
    are resolved by `RendererToAgentMessageProcessor` with the catalog's agent
    function handlers and replied to with a single A2A Message holding the
    `agentFunctionResponse`. No session event and no model call is produced.
    """

    def __init__(self, inner: AgentExecutor) -> None:
        self._inner = inner
        self._rpc = RendererToAgentMessageProcessor(
            get_a2ui_processor().active_catalogs, agent_function_timeout=5.0
        )

    async def execute(self, context: RequestContext, event_queue: EventQueue) -> None:
        message = context.message
        parts = list(message.parts) if message is not None else []
        calls = [
            payload
            for payload in (_data_part_payload(p) for p in parts)
            if payload is not None and "callAgentFunction" in payload
        ]
        if not calls or len(calls) != len(parts):
            _check_renderer_capabilities(message)
            await self._inner.execute(context, event_queue)
            return

        reply_parts: list[a2a_types.Part] = []
        for call in calls:
            try:
                result = await self._rpc.process_message(call)
            except A2uiError as exc:
                logger.warning("Rejected callAgentFunction: %s", exc)
                continue
            reply_parts.extend(
                _a2ui_data_part(reply.model_dump(by_alias=True, exclude_unset=True))
                for reply in result.replies
            )
        await event_queue.enqueue_event(
            _compat.make_message(
                message_id=uuid.uuid4().hex,
                role="agent",
                parts=reply_parts,
                context_id=context.context_id,
            )
        )

    async def cancel(self, context: RequestContext, event_queue: EventQueue) -> None:
        await self._inner.cancel(context, event_queue)


def _check_renderer_capabilities(message: Any) -> None:
    """Negotiates catalogs for the renderer that sent `message` and logs a mismatch.

    `A2uiGenerator.create_processor` raises when the renderer supports none of
    the agent's catalogs; the agent keeps answering with its default catalog so
    the problem is visible in the logs rather than as a hard failure.
    """
    metadata = _compat.meta_to_dict(getattr(message, "metadata", None))
    try:
        get_a2ui_generator().create_processor(
            renderer_capabilities_from_metadata(metadata)
        )
    except A2uiError as exc:
        logger.warning("Renderer capabilities do not match the agent catalog: %s", exc)


async def attach_a2a_routes(
    app: FastAPI,
    *,
    agent: BaseAgent,
    runner: Runner,
    task_store: TaskStore,
    rpc_path: str,
    capabilities: AgentCapabilities | None = None,
    agent_version: str | None = None,
    app_url: str | None = None,
) -> None:
    """Register A2A routes (JSON-RPC + agent-card endpoints) under ``rpc_path``."""
    resolved_app_url = app_url or os.getenv("APP_URL", "http://0.0.0.0:8000")
    resolved_agent_version = agent_version or os.getenv("AGENT_VERSION", "0.1.0")
    resolved_capabilities = capabilities or _default_capabilities()

    agent_card = await AgentCardBuilder(
        agent=agent,
        capabilities=resolved_capabilities,
        rpc_url=f"{resolved_app_url}{rpc_path}",
        agent_version=resolved_agent_version,
    ).build()

    agent_card = _add_v0_3_compat_interface(agent_card)

    executor_config = A2aAgentExecutorConfig(
        a2a_part_converter=convert_snap_sell_a2a_part_to_genai,
        gen_ai_part_converter=convert_snap_sell_genai_part_to_a2a,
    )
    request_handler = DefaultRequestHandler(
        agent_executor=SnapSellA2uiExecutor(
            A2aAgentExecutor(
                runner=runner,
                force_new_version=False,
                config=executor_config,
            )
        ),
        task_store=task_store,
        agent_card=agent_card,
    )

    add_a2a_routes_to_fastapi(
        app,
        agent_card_routes=create_agent_card_routes(
            agent_card,
            card_url=f"{rpc_path}{AGENT_CARD_WELL_KNOWN_PATH}",
        ),
        jsonrpc_routes=create_jsonrpc_routes(
            request_handler,
            rpc_url=rpc_path or "/",
            enable_v0_3_compat=True,
        ),
    )
