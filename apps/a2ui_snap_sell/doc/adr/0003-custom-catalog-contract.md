# 0003. Shared Custom A2UI Catalog Contract (`BasicCatalog` + 5 Custom Components)

- **Status**: accepted
- **Date**: 2026-10-21
- **Deciders**: flutter-architect

## Context

In A2UI `v0.9`, every `createSurface` message specifies a single `catalogId`, and both the Python `PayloadValidator` (`a2ui-core == 0.4.0`) and Flutter `SurfaceController` (`genui ^0.10.4`) validate all components on that surface against the schema registered for that `catalogId`. Furthermore, Track A (`agent/` in Python) and Track B (`mobile/` in Flutter) will be implemented in parallel by separate agents in State 2. Any mismatch in component names, property schemas, data-binding paths, or `UserActionEvent` names/contexts would break integration.

## Decision

Define a **single unified catalog contract** in `apps/a2ui_snap_sell/contracts/` (read-only during State 2) with canonical `catalogId`:
`https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json`

1. **Contract Artifacts**:
   - `apps/a2ui_snap_sell/contracts/snap_sell_catalog.json`: A complete A2UI `v0.9` JSON Schema catalog document (`protocolVersion: "0.9"`) containing the 12 required `BasicCatalog` components (`Text`, `Image`, `Icon`, `Row`, `Column`, `Card`, `Divider`, `Button`, `TextField`, `CheckBox`, `ChoicePicker`, `Slider`), standard A2UI functions (`required`, `regex`, `length`, `numeric`, `email`, `formatString`, `formatNumber`, `formatCurrency`, `formatDate`, `pluralize`, `openUrl`, `and`, `or`, `not`), and **5 domain-specific custom components**:
     1. `StepProgress`: Renders the multi-step progress header (`currentStep`, `totalSteps`, `stepLabels`, optional `subtitle`).
     2. `DetectedItemCard`: Displays the uploaded item photo, category badge (`car` | `motorcycle` | `phone`), AI confidence score, summary, optional EV badge, and a list of pre-filled editable `fields` (`{key, label, value, variant}`) bound to `/detected/<key>` paths in the `DataModel`.
     3. `PhotoRequest`: Renders a camera/gallery capture card for conditional follow-up photos (`requestType`: `damage` | `odometer` | `extra`, `title`, `instructions`, `actionName`, `targetPath`, `previewUrl`, `required`). Tapping its capture button triggers `ImagePicker` on the device and sends the action + compressed `FilePart` image bytes to the agent.
     4. `PriceRange`: Renders a visual min / suggested / max price gauge with currency formatting, pricing rationale, and an interactive slider/input bound to `selectedPrice` (`/pricing/askingPrice`).
     5. `ListingPreview`: Renders the final marketplace listing preview card (photo carousel `imageUrls`, `title`, `description`, `category`, `price`, `currency`, key-value `specs` chips, `missingChecklist` items, and a primary `publishAction` button).
   - `apps/a2ui_snap_sell/contracts/CATALOG_CONTRACT.md`: Normative specification of component props, canonical `DataModel` paths (`/detected/*`, `/details/*`, `/followup/*`, `/pricing/*`, `/preview/*`), and client→server `UserActionEvent` contracts (`submit_detected_details`, `request_odometer_scan`, `upload_followup_photo`, `submit_followup`, `publish_listing`, `start_new_listing`).
   - `apps/a2ui_snap_sell/contracts/examples/0.9/*.json`: 5 complete, schema-valid v0.9 A2UI message arrays used both as few-shot examples in the Python agent prompt and as golden test fixtures in Python `pytest` and Flutter `flutter test`.
2. **Consumption by Both Tracks**:
   - **Python (`agent/`)**: Loads `../contracts/snap_sell_catalog.json` directly via `CatalogConfig.from_path(...)` and loads `../contracts/examples/0.9/*.json` into `A2uiGenerator`.
   - **Flutter (`mobile/`)**: Constructs `snapSellCatalog` via `BasicCatalogItems.asCatalog().copyWith(catalogId: snapSellCatalogId, catalogIdAliases: [basicCatalogId, legacyBasicCatalogId], newItems: [stepProgressItem, detectedItemCardItem, photoRequestItem, priceRangeItem, listingPreviewItem])` where each custom `CatalogItem` uses `json_schema_builder` (`S.object(...)`) matching `snap_sell_catalog.json` property-for-property.

## Alternatives considered

- **Using only `BasicCatalog` without custom components** — rejected because `PhotoRequest` (which must invoke native `ImagePicker` and attach binary `FilePart` bytes to an action), `DetectedItemCard` (photo + confidence + inline bound fields), `PriceRange` (min/suggested/max visual gauge), `ListingPreview`, and `StepProgress` cannot be expressed cleanly with generic `BasicCatalog` primitives alone, and custom catalog items are a core requirement of the architecture.
- **Keeping separate catalog definitions in `agent/` and `mobile/`** — rejected because parallel implementation tracks would inevitably drift on property names, required fields, or action payload shapes.
- **Putting custom components in a separate `catalogId` from `BasicCatalog`** — rejected because in A2UI `v0.9`, `createSurface` binds a surface to a single `catalogId`; bundling the 12 `BasicCatalog` components and 5 custom components under one `catalogId` allows a single surface to freely compose `Column`, `Card`, `TextField`, `ChoicePicker`, `CheckBox`, `Button` alongside `StepProgress`, `DetectedItemCard`, `PhotoRequest`, `PriceRange`, and `ListingPreview`.

## Consequences

- **Positive**: Zero schema drift between Track A and Track B; both tracks validate against the exact same JSON files in `contracts/`.
- **Positive**: Dropping unused `BasicCatalog` components (`AudioPlayer`, `Video`, `Tabs`, `Modal`, `DateTimeInput`, `List`) from `snap_sell_catalog.json` reduces system prompt token size and improves Gemini Flash latency.
- **Trade-off**: Any change to component properties during State 2 requires orchestrator approval to update `contracts/`.

## Compliance

`flutter-reviewer` and Track A/B reviewers check:
-Neither Track A nor Track B modifies `apps/a2ui_snap_sell/contracts/**` during State 2 without orchestrator routing.
- Every custom `CatalogItem.name` and `dataSchema` in `mobile/lib/ui/catalog/` matches `contracts/snap_sell_catalog.json` and `contracts/CATALOG_CONTRACT.md` exactly.
- Both `agent/tests/test_catalog_contract.py` and `mobile/test/unit/catalog/snap_sell_catalog_test.dart` parse and validate all 5 JSON files in `contracts/examples/0.9/`.
