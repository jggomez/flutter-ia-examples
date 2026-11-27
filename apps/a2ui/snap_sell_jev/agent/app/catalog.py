"""A2UI v1.0 catalog for Snap & Sell (Jev variant): validation and agent functions.

No model writes UI in this variant, so there is no Express prompt here. The
catalog is used to:

* validate every surface `app.surfaces` assembles (`validate_a2ui_payload`),
* negotiate renderer capabilities, and
* answer `priceFeedback` agent-function calls (`callAgentFunction`).
"""

from __future__ import annotations

import functools
import json
import os
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from a2ui.core import AgentFunction
from a2ui.core.schema import ProtocolVersion
from a2ui.inference_formats import ExpressFormatFactory
from a2ui.processor import A2uiGenerator, A2uiRequestProcessor, CatalogConfig
from a2ui.utils import read_renderer_capabilities, validate_payload

from app.tools import price_feedback

SNAP_SELL_CATALOG_ID = "https://snap-sell.devhack.dev/a2ui/v1.0/snap_sell_catalog.json"
A2UI_VERSION_KEY = "1.0"

STAGE_SURFACE_IDS: tuple[str, ...] = (
    "selling_step_1_detected",
    "selling_step_2_followup",
    "selling_step_3_preview",
    "selling_step_4_published",
    "selling_unsupported",
)

#: Capabilities assumed when a request does not carry `a2uiRendererCapabilities`
#: (for example the ADK dev UI). The Snap & Sell app always sends them.
DEFAULT_RENDERER_CAPABILITIES: dict[str, Any] = {
    A2UI_VERSION_KEY: {"supportedCatalogIds": [SNAP_SELL_CATALOG_ID]}
}


def resolve_contracts_dir() -> Path:
    """Resolves the directory containing snap_sell_catalog.json across dev and Docker environments."""
    env_override = os.getenv("SNAP_SELL_CONTRACTS_DIR")
    base_dir = Path(__file__).resolve().parent
    candidates = [
        Path(env_override) if env_override else None,
        (base_dir / ".." / ".." / "contracts").resolve(),
        (base_dir / ".." / "contracts").resolve(),
        Path("./contracts").resolve(),
        Path("/code/contracts"),
    ]
    for candidate in candidates:
        if candidate is not None and (candidate / "snap_sell_catalog.json").exists():
            return candidate
    raise FileNotFoundError(
        "Could not locate snap_sell_catalog.json in ../../contracts or ./contracts."
    )


@functools.cache
def get_catalog_config() -> CatalogConfig:
    """Loads the v1.0 catalog and binds the `priceFeedback` agent function handler."""
    base = CatalogConfig.from_path(
        str(resolve_contracts_dir() / "snap_sell_catalog.json"),
        protocol_version=ProtocolVersion.V1_0,
        catalog_id=SNAP_SELL_CATALOG_ID,
    ).catalog
    declared = base.functions["priceFeedback"]
    catalog = base.copy_with(
        agent_functions=[AgentFunction.from_api(declared, price_feedback)]
    )
    return CatalogConfig(catalog=catalog)


@functools.cache
def get_a2ui_generator() -> A2uiGenerator:
    """Agent-level generator: one catalog, v1.0 few-shot examples, Express format."""
    examples_dir = resolve_contracts_dir() / "examples" / "1.0"
    examples = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in sorted(examples_dir.glob("*.json"))
    ]
    return A2uiGenerator(
        [get_catalog_config()],
        examples=examples or None,
        inference_format_factory=ExpressFormatFactory(),
    )


def renderer_capabilities_from_metadata(
    metadata: Mapping[str, Any] | None,
) -> dict[str, Any]:
    """Reads v1.0 `a2uiRendererCapabilities` from transport metadata, with a default."""
    return read_renderer_capabilities(metadata) or DEFAULT_RENDERER_CAPABILITIES


@functools.cache
def get_a2ui_processor() -> A2uiRequestProcessor:
    """Processor negotiated for the Snap & Sell renderer (the only renderer of this agent).

    `create_processor` is the per-request negotiation step: an agent serving
    several renderers would call it with each request's capabilities (see
    `renderer_capabilities_from_metadata`). Snap & Sell has one renderer and a
    static system prompt, so the negotiated processor is cached.
    """
    return get_a2ui_generator().create_processor(DEFAULT_RENDERER_CAPABILITIES)


def validate_a2ui_payload(payload: list[Any] | dict[str, Any]) -> None:
    """Validates A2UI v1.0 wire messages against the Snap & Sell catalog."""
    processor = get_a2ui_processor()
    validate_payload(processor.active_catalogs, payload)  # type: ignore[arg-type]
