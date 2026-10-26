# Snap & Sell — Python ADK Agent Backend

The Python Agent Development Kit backend for **Snap & Sell**, powered by Gemini Vision on Vertex AI and the Agent-to-UI protocol.

This agent receives item photos and seller actions from the Flutter mobile app, identifies the product using multimodal vision, runs pricing and validation tools, and streams back dynamic UI surfaces tailored to the item being sold.

For the complete overview of Snap & Sell, see the main [Snap & Sell README](../README.md).

---

## How the Agent Works

1. **Multimodal Item Recognition**: Analyzes uploaded item photos with Gemini Vision to identify the product category, brand, model, condition, and visible attributes.
2. **Adaptive Follow-Up Logic**: Determines which category-specific fields are required and whether visual verification—such as a dashboard odometer photo for a car or motorcycle—is needed.
3. **Marketplace Tools**:
   - Records the detected item profile and required attributes.
   - Validates seller-submitted details for completeness and plausibility.
   - Extracts mileage from follow-up odometer photos and cross-checks manual entries.
   - Estimates a recommended market price range and assembles the final listing preview.
4. **Schema-Validated UI Generation**: Composes each screen using the shared Snap & Sell component catalog and validates the generated UI definition before streaming it to the mobile client.

---

## Built With & References

- [Google Agent Development Kit](https://google.github.io/adk-docs/) — Agent orchestration and tool execution with Gemini on Vertex AI.
- [`a2ui-agent-sdk`](https://pypi.org/project/a2ui-agent-sdk/) — Agent-to-UI schema generation and surface validation.
- [`a2a-sdk`](https://pypi.org/project/a2a-sdk/) — Agent-to-Agent streaming server transport.

---

## Getting Started

```bash
cd apps/a2ui_snap_sell/agent
uv sync
uv run uvicorn app.fast_api_app:app --host 0.0.0.0 --port 8000 --reload
```
