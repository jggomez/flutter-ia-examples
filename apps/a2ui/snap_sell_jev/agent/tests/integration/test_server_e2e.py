"""FastAPI integration tests for health, AgentCard endpoints, and uploads mount."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from app.app_utils.a2a import A2UI_EXTENSION_URI, A2UI_MIME_TYPE
from app.catalog import SNAP_SELL_CATALOG_ID
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


def test_a2a_stream_returns_jev_built_surface_as_datapart() -> None:
    """Full wire path the Flutter app uses: A2A v0.3 `message/stream` over SSE."""
    import base64
    import json

    from app.agent import JEV_TRACE_MIME_TYPE, root_agent
    from app.flow import SellingFlow
    from tests.unit.fakes import FakeJev, FakeWriter

    root_agent.flow = SellingFlow(FakeJev(), FakeWriter())
    photo = base64.b64encode(b"\xff\xd8\xff\xe0fake-jpeg").decode()
    body = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "message/stream",
        "params": {
            "message": {
                "kind": "message",
                "role": "user",
                "messageId": "m1",
                "parts": [
                    {"kind": "text", "text": "Analyze this item."},
                    {
                        "kind": "file",
                        "file": {
                            "bytes": photo,
                            "mimeType": "image/jpeg",
                            "name": "car.jpg",
                        },
                    },
                ],
            }
        },
    }
    with TestClient(app) as client:
        resp = client.post("/", json=body, headers={"Accept": "text/event-stream"})
    assert resp.status_code == 200
    data_parts: list[dict] = []
    for line in resp.text.splitlines():
        if not line.startswith("data:"):
            continue
        result = json.loads(line[5:]).get("result", {})
        holders = [
            result.get("status", {}).get("message", {}),
            result.get("artifact", {}),
            result,
        ]
        for holder in holders:
            for part in holder.get("parts", []) or []:
                if part.get("kind") == "data":
                    data_parts.append(part)
    mimes = {p.get("metadata", {}).get("mimeType") for p in data_parts}
    assert {A2UI_MIME_TYPE, JEV_TRACE_MIME_TYPE} <= mimes
    surface = next(
        p["data"] for p in data_parts if p["metadata"]["mimeType"] == A2UI_MIME_TYPE
    )
    assert surface["createSurface"]["surfaceId"] == "selling_step_1_detected"
