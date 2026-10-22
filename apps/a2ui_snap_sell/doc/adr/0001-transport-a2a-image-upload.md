# 0001. System Architecture, A2A Transport, and Image Upload Pipeline

- **Status**: accepted
- **Date**: 2026-10-21
- **Deciders**: flutter-architect

## Context

`apps/a2ui_snap_sell` ("Snap & Sell") is a client/server generative UI application where a mobile user snaps or selects a photo of an item to sell (v1 categories: car, motorcycle, phone) on a fixed entry screen, and a remote Python ADK agent (Gemini multimodal on Vertex AI, hosted on Cloud Run) dynamically generates all subsequent screens as A2UI surfaces.

Verified ground-truth package versions and protocol capabilities:
- **Flutter client**: `genui ^0.10.4` (depends on `a2ui_core ^0.1.0`, `json_schema_builder ^0.1.3`), `genui_a2a ^0.10.1` (`A2uiAgentConnector`, `A2AClient`, `SseTransport`), `image_picker ^1.2.4`, `mime ^2.0.0`.
- **Python agent (`agents-cli` ADK scaffold)**: Created via `agents-cli scaffold create` (`google-agents-cli ~= 1.11.0`) with `google-adk >= 2.12.0`, `a2a-sdk[http-server] >= 1.0, < 2.0`, `a2ui-agent-sdk == 0.9.0` (`a2ui-core == 0.4.0`), and `google-genai >= 2.32.0`.
- **Protocol**: A2UI `v0.9` over A2A JSON-RPC + Server-Sent Events (`message/stream`), advertised and negotiated via extension URI `https://a2ui.org/a2a-extension/a2ui/v0.9` (`X-A2A-Extensions` header) and A2A `DataPart` metadata `{"mimeType": "application/json+a2ui"}`.

We must decide how the Flutter app connects to the Python agent and how user photos (initial item photo plus conditional follow-up photos such as damage or odometer shots) travel from the device to Gemini and back into rendered UI surfaces without hand-rolling a custom web server or custom A2A executor from scratch.

## Decision

1. **Transport via `agents-cli` FastAPI + ADK Built-in `A2aAgentExecutor`**:
   - Use **`genui_a2a ^0.10.1` (`A2uiAgentConnector`)** wired to **`genui ^0.10.4` (`A2uiTransportAdapter` + `SurfaceController` + `Conversation`)** communicating over HTTP/HTTPS A2A JSON-RPC + SSE (`message/stream`) with the `agents-cli` scaffolded FastAPI server (`app/fast_api_app.py` + `app/app_utils/a2a.py`).
   - Instead of writing a custom `AgentExecutor`, use ADK's built-in `google.adk.a2a.executor.a2a_agent_executor.A2aAgentExecutor` configured with `force_new_version=False` (so `TaskStatusUpdateEvent` events carry `status.message.parts` as expected by `genui_a2a`'s `A2uiAgentConnector`) and `A2aAgentExecutorConfig(a2a_part_converter=..., gen_ai_part_converter=...)`.
   - Extend `AgentCardBuilder` in `app/app_utils/a2a.py` with `AgentCapabilities(streaming=True, extensions=[AgentExtension(uri="https://a2ui.org/a2a-extension/a2ui/v0.9", ...)])` and mount A2A routes at both `/a2a/app` (standard `agents-cli` path) and `/` for direct root A2A compatibility.
2. **In-band Image Upload via A2A `FilePart` Bytes & ADK Part Converters**:
   - Send photos in-band inside `ChatMessage.user('', parts: [UiInteractionPart.create(actionJson), DataPart(imageBytes, mimeType: 'image/jpeg')])`.
   - `A2uiAgentConnector.connectAndSend` converts `UiInteractionPart` into an A2A `DataPart` (`{"version": "v0.9", "action": {...}}`) and `genui.DataPart(bytes, mimeType)` into an A2A `FilePart` with base64 bytes.
   - On the Python server, ADK's built-in `convert_a2a_part_to_genai_part` automatically decodes incoming A2A `FilePart` bytes into `google.genai.types.Part(inline_data=Blob(...))` for Gemini multimodal vision. Our thin `a2a_part_converter` wrapper in `app/app_utils/a2a.py`:
     1. Saves a copy of incoming `FilePart` image bytes to `/tmp/snap_sell_uploads/<uuid>.jpg` (served via FastAPI `StaticFiles` at `/uploads/<uuid>.jpg`) and appends the image URL so the agent can reference the user's real photo inside `DetectedItemCard`, `ListingPreview`, and `Image` components.
     2. Converts incoming A2UI `DataPart` client actions (`{"version": "v0.9", "action": {...}}`) into structured text instructions for `root_agent`.
   - Our thin `gen_ai_part_converter` wrapper parses `<a2ui-json>...</a2ui-json>` blocks from Gemini's text output using `a2ui.processor.A2uiRequestProcessor` + `a2ui.parser.Parser` and emits validated A2UI messages as A2A `DataPart`s (`metadata={"mimeType": "application/json+a2ui"}`) via `google.adk.a2a._compat.make_data_part`.
3. **Device-Side Image Compression**: Configure `ImagePicker.pickImage` with `maxWidth: 1280`, `maxHeight: 1280`, `imageQuality: 80` (hard cap: reject if `bytes.lengthInBytes > 1_500_000`).

## Alternatives considered

- **Hand-writing a custom Starlette server, custom `SnapSellAgentExecutor`, and custom `AdkRunnerBackend`** — rejected because `agents-cli scaffold create --agent adk --deployment-target cloud_run` already provides production-grade `app/fast_api_app.py`, `app/app_utils/a2a.py`, `A2aAgentExecutor`, `AgentCardBuilder`, OpenTelemetry setup, Terraform deployment, and CLI tooling (`agents-cli run`, `playground`, `lint`, `eval`, `deploy`).
- **GCS Signed URL out-of-band upload** — rejected for v1 because in-band `FilePart` at 1280px/Q80 is <500 KB on the wire and works identically on local emulator and Cloud Run.

## Consequences

- **Positive**: Preserves 100% of the official `agents-cli` scaffold (`agents-cli-manifest.yaml`, `app/fast_api_app.py`, `app/app_utils/services.py`, `Dockerfile`, `deployment/terraform/`) while adding A2UI v0.9 support purely through ADK's `A2aAgentExecutorConfig` converters and `AgentCardBuilder`.
- **Trade-off**: Ephemeral `/tmp/snap_sell_uploads` storage on Cloud Run is local to the container instance; prototype Cloud Run deployments should keep session affinity / single instance for v1 demo previews.

## Compliance

`flutter-reviewer` and Track A/B reviewers check:
- `mobile/pubspec.yaml` pins `genui: ^0.10.4`, `genui_a2a: ^0.10.1`, `json_schema_builder: ^0.1.7`, `image_picker: ^1.2.4`, `mime: ^2.0.0`.
- `agent/` is scaffolded with `agents-cli` (`agents-cli-manifest.yaml` present, `agents-cli info` and `agents-cli lint` succeed) and includes `a2ui-agent-sdk>=0.9.0,<0.10.0`.
- Image picking always passes `maxWidth: 1280`, `maxHeight: 1280`, `imageQuality: 80` and enforces a 1.5 MB byte-size guard before calling `sendRequest`.
- No `A2uiAgentConnector` or `http` imports appear in `mobile/lib/ui/**` or `mobile/lib/domain/**` (isolated in `mobile/lib/data/**`).
