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

"""Attach A2A (Agent2Agent) endpoints and A2UI v0.9 part converters to the FastAPI app."""

from __future__ import annotations

import json
import logging
import os
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, Any

from a2a import types as a2a_types
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
from a2ui.parser import A2uiPart, TextPart, to_message_dicts
from google.adk.a2a import _compat
from google.adk.a2a.converters.part_converter import (
    convert_a2a_part_to_genai_part,
    convert_genai_part_to_a2a_part,
)
from google.adk.a2a.executor.a2a_agent_executor import A2aAgentExecutor
from google.adk.a2a.executor.config import A2aAgentExecutorConfig
from google.adk.a2a.utils.agent_card_builder import AgentCardBuilder
from google.genai import types as genai_types

from app.catalog import (
    BASIC_CATALOG_ID,
    SNAP_SELL_CATALOG_ID,
    get_a2ui_processor,
)

if TYPE_CHECKING:
    from fastapi import FastAPI
    from google.adk.agents import BaseAgent
    from google.adk.runners import Runner

logger = logging.getLogger(__name__)

_ADK_AGENT_EXECUTOR_EXTENSION_URI = (
    "https://google.github.io/adk-docs/a2a/a2a-extension/"
)
A2UI_EXTENSION_URI = "https://a2ui.org/a2a-extension/a2ui/v0.9"
A2UI_MIME_TYPE = "application/json+a2ui"
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
    """Returns the default A2A capabilities advertising A2UI v0.9 support."""
    return AgentCapabilities(
        streaming=True,
        extensions=[
            AgentExtension(
                uri=A2UI_EXTENSION_URI,
                description="Supports A2UI v0.9 dynamic surface generation for Snap & Sell",
                required=False,
                params={
                    "supportedCatalogIds": [
                        SNAP_SELL_CATALOG_ID,
                        BASIC_CATALOG_ID,
                    ]
                },
            ),
            AgentExtension(
                uri=_ADK_AGENT_EXECUTOR_EXTENSION_URI,
                description="Ability to use the new agent executor implementation",
            ),
        ],
    )


def _extract_action_from_data_part(part: a2a_types.Part) -> dict[str, Any] | None:
    """Extracts an A2UI client action dict from an A2A DataPart if present."""
    if _compat.is_data_part(part):
        data_dict = _compat.data_part_dict(part)
        if isinstance(data_dict, dict):
            if isinstance(data_dict.get("action"), dict):
                return dict(data_dict["action"])
            if isinstance(data_dict.get("event"), dict):
                return dict(data_dict["event"])
    root = getattr(part, "root", part)
    raw_data = getattr(root, "data", None)
    if isinstance(raw_data, dict):
        if isinstance(raw_data.get("action"), dict):
            return dict(raw_data["action"])
        if isinstance(raw_data.get("event"), dict):
            return dict(raw_data["event"])
    return None


def convert_snap_sell_a2a_part_to_genai(
    part: a2a_types.Part,
) -> genai_types.Part | list[genai_types.Part] | None:
    """Converts incoming A2A parts (A2UI client actions and uploaded photos) into GenAI parts."""
    action = _extract_action_from_data_part(part)
    if action is not None:
        action_name = str(action.get("name", "unknown_action"))
        surface_id = str(action.get("surfaceId", "entry"))
        context_obj = action.get("context", {})
        context_json = json.dumps(context_obj, ensure_ascii=False)
        return genai_types.Part.from_text(
            text=(
                f"User triggered A2UI action '{action_name}' on surface '{surface_id}' "
                f"with context: {context_json}"
            )
        )

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


def convert_snap_sell_genai_part_to_a2a(
    part: genai_types.Part,
) -> a2a_types.Part | list[a2a_types.Part] | None:
    """Converts GenAI text parts containing <a2ui-json> blocks into A2A DataParts."""
    if part.text and "<a2ui-json>" in part.text:
        processor = get_a2ui_processor()
        parser = processor.create_parser()
        try:
            response_parts = parser.parse_response(part.text, wrapped=True)
            output_parts: list[a2a_types.Part] = []
            for resp_part in response_parts:
                if isinstance(resp_part, TextPart):
                    cleaned = resp_part.text.strip()
                    if cleaned:
                        output_parts.append(_compat.make_text_part(cleaned))
                elif isinstance(resp_part, A2uiPart):
                    for msg_dict in to_message_dicts(resp_part.a2ui):
                        output_parts.append(
                            _compat.make_data_part(
                                data=msg_dict,
                                metadata={"mimeType": A2UI_MIME_TYPE},
                            )
                        )
            if output_parts:
                return output_parts
        except A2uiError as exc:
            logger.warning(
                "Failed to parse <a2ui-json> block into A2A DataPart: %s", exc
            )

    return convert_genai_part_to_a2a_part(part)


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
        agent_executor=A2aAgentExecutor(
            runner=runner,
            force_new_version=False,
            config=executor_config,
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
