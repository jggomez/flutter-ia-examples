# Snap & Sell — Flutter GenUI Mobile Client

The Flutter mobile application for **Snap & Sell**, built with Flutter GenUI and the Agent-to-UI protocol.

Instead of hardcoding multi-step listing forms for every product category, the mobile client ships a single photo capture screen. Once the seller takes or chooses a photo of an item, the remote AI agent analyzes the image and dynamically streams the UI screens needed to complete the listing.

For the complete overview of Snap & Sell, see the main [Snap & Sell README](../README.md).

---

## How the GenUI Client Works

1. **Photo Capture Entry**: The seller captures or selects a photo of an item to sell.
2. **Agent-to-Agent Streaming**: The app streams the photo and user interactions to the remote ADK agent and receives live UI surface updates.
3. **Custom GenUI Widget Catalog**: Incoming AI surface definitions are rendered as native Flutter widgets using a custom marketplace catalog:
   - **Step Progress**: Guides the seller through item recognition, details, pricing, and publication.
   - **Detected Item Card**: Displays the recognized product category, brand, model, and pre-filled attributes.
   - **Photo Request Card**: Prompts the seller for follow-up verification photos—such as a vehicle odometer reading or close-up condition check—only when needed.
   - **Price Range Card**: Visualizes the recommended market price band with an interactive price selector.
   - **Listing Preview Card**: Lets the seller review and edit the generated title, price, and description before publishing.

---

## Built With & References

- [`genui`](https://pub.dev/packages/genui) — Flutter GenUI SDK for rendering dynamic AI-driven widget surfaces.
- [`genui_a2a`](https://pub.dev/packages/genui_a2a) — Agent-to-Agent streaming client for Flutter GenUI.
- [`a2ui_core`](https://pub.dev/packages/a2ui_core) — Core primitives for the Agent-to-UI protocol.

---

## Getting Started

```bash
cd apps/a2ui_snap_sell/mobile
flutter pub get
flutter run --dart-define-from-file=config/prod.json
```
