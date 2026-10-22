"""FastAPI integration tests for health, AgentCard endpoints, and uploads mount."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.app_utils.a2a import A2UI_EXTENSION_URI
from app.catalog import BASIC_CATALOG_ID, SNAP_SELL_CATALOG_ID
from app.fast_api_app import UPLOAD_DIR, app


def test_health_and_agent_cards_include_a2ui_extension() -> None:
    """Verifies /health, /.well-known/agent-card.json, and /a2a/app/.well-known/agent-card.json."""
    with TestClient(app) as client:
        health_resp = client.get("/health")
        assert health_resp.status_code == 200
        assert health_resp.json() == {"status": "ok"}

        for card_path in (
            "/.well-known/agent-card.json",
            "/a2a/app/.well-known/agent-card.json",
        ):
            resp = client.get(card_path)
            assert resp.status_code == 200, f"{card_path} returned {resp.status_code}"
            card = resp.json()
            assert card.get("name") == "snap_sell_agent"
            caps = card.get("capabilities", {})
            assert caps.get("streaming") is True
            extensions = caps.get("extensions", [])
            a2ui_exts = [
                ext for ext in extensions if ext.get("uri") == A2UI_EXTENSION_URI
            ]
            assert len(a2ui_exts) == 1
            params = a2ui_exts[0].get("params", {})
            supported = params.get("supportedCatalogIds", [])
            assert SNAP_SELL_CATALOG_ID in supported
            assert BASIC_CATALOG_ID in supported


def test_uploads_static_mount_serves_uploaded_files() -> None:
    """Verifies /uploads static directory serves files written to UPLOAD_DIR."""
    Path(UPLOAD_DIR).mkdir(parents=True, exist_ok=True)
    sample_file = Path(UPLOAD_DIR) / "test_photo.jpg"
    sample_bytes = b"\xff\xd8\xff\xd9"
    sample_file.write_bytes(sample_bytes)

    with TestClient(app) as client:
        resp = client.get("/uploads/test_photo.jpg")
        assert resp.status_code == 200
        assert resp.content == sample_bytes
