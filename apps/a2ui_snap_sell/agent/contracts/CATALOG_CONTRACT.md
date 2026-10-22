# Snap & Sell — Shared A2UI v0.9 Catalog Contract

> **Single Source of Truth** for Track A (`apps/a2ui_snap_sell/agent/`) and Track B (`apps/a2ui_snap_sell/mobile/`).
> Read-only during State 2 parallel execution.

## 1. Protocol & Catalog Identifiers

| Constant | Value |
|---|---|
| A2UI Protocol Version | `v0.9` (`ProtocolVersion.V0_9` in Python) |
| A2A Extension URI | `https://a2ui.org/a2a-extension/a2ui/v0.9` |
| A2UI DataPart MIME | `application/json+a2ui` (accepted alongside `application/a2ui+json`) |
| Canonical `catalogId` | `https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json` |
| Flutter `catalogIdAliases` | `["https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json", "https://a2ui.org/specification/v0_9/basic_catalog.json", "snap_sell_catalog"]` |
| Schema File | [`snap_sell_catalog.json`](./snap_sell_catalog.json) |
| Few-Shot & Test Fixtures | [`examples/0.9/`](./examples/0.9/) (`01_detected_car.json` .. `05_unsupported_item.json`) |

---

## 2. Canonical Surface IDs

The agent emits one stable `surfaceId` per flow stage so the Flutter client can maintain a back-navigable surface stack while supporting in-place updates for validation errors or OCR pre-fills:

| `surfaceId` | When Emitted | Root Composition |
|---|---|---|
| `selling_unsupported` | Photo is not a car, motorcycle, or phone | `Card` → `Icon("warning")` + `Text` + `Button("start_new_listing")` |
| `selling_step_1_detected` | Item identified (`car`, `motorcycle`, `phone`) | `Column` → `StepProgress(1/4)` + `DetectedItemCard` + `Card` (category questions) + `Button("submit_detected_details")` |
| `selling_step_2_followup` | Conditional follow-up needed (`hasDamage == true`, odometer scan requested, or validation errors) | `Column` → `StepProgress(2/4)` + 1..2 `PhotoRequest` cards + `TextField` notes + `Button("submit_followup")` |
| `selling_step_3_preview` | All required fields & follow-ups valid | `Column` → `StepProgress(3/4)` + `PriceRange` + `ListingPreview` |
| `selling_step_4_published` | User taps `publish_listing` | `Column` → `StepProgress(4/4)` + `Card` (published confirmation + listing summary + `Button("start_new_listing")`) |

---

## 3. Custom Component Specifications

All 5 custom components are defined in [`snap_sell_catalog.json`](./snap_sell_catalog.json) and implemented in `mobile/lib/ui/catalog/items/`.

### 3.1 `StepProgress`
Renders a horizontal step indicator at the top of a selling stage.

| Property | JSON Schema Type | Required | Description |
|---|---|---|---|
| `component` | `"StepProgress"` | ✅ | Discriminator |
| `currentStep` | `integer` (`>= 1`) | ✅ | 1-based index of the active step |
| `totalSteps` | `integer` (`>= 1`) | ✅ | Total steps (`4`) |
| `stepLabels` | `array<string>` (`minItems: 1`) | ✅ | e.g. `["Detected", "Follow-up", "Preview", "Published"]` |
| `subtitle` | `DynamicString` | ❌ | Optional step guidance subtitle |

### 3.2 `DetectedItemCard`
Displays the uploaded item photo, detected category badge, confidence chip, optional EV badge, summary, and inline editable pre-filled fields bound to `/detected/<key>`.

| Property | JSON Schema Type | Required | Description |
|---|---|---|---|
| `component` | `"DetectedItemCard"` | ✅ | Discriminator |
| `category` | `"car" \| "motorcycle" \| "phone"` | ✅ | Detected item category |
| `imageUrl` | `DynamicString` | ✅ | Uploaded photo URL (`{"path": "/detected/imageUrl"}` or string) |
| `confidence` | `number` (`0.0..1.0`) | ✅ | Vision confidence score (rendered as percentage badge, e.g. `94% match`) |
| `summary` | `DynamicString` | ✅ | Short summary of visual detection |
| `isEv` | `boolean` | ❌ | If `true`, displays an `"EV / Electric"` badge |
| `fields` | `array<Object>` (`minItems: 1`) | ✅ | List of `{key: string, label: string, value: DynamicString, editable?: boolean}`. When `value` is `{"path": "/detected/<key>"}`, editing updates `itemContext.dataContext` in place |

### 3.3 `PhotoRequest`
Prompts the user to capture/pick a follow-up photo (damage close-up, odometer reading, or extra angle).

| Property | JSON Schema Type | Required | Description |
|---|---|---|---|
| `component` | `"PhotoRequest"` | ✅ | Discriminator |
| `requestType` | `"damage" \| "odometer" \| "extra"` | ✅ | Controls icon and semantic label |
| `title` | `DynamicString` | ✅ | Card heading |
| `instructions` | `DynamicString` | ✅ | Capture instructions |
| `actionName` | `string` | ✅ | Action name sent when photo is picked (`"upload_followup_photo"`) |
| `targetPath` | `string` | ✅ | `DataModel` path updated with local/remote preview URI (`"/followup/odometerPhotoUrl"` or `"/followup/damagePhotoUrl"`) |
| `previewUrl` | `DynamicString` | ❌ | Optional bound path or URL of already-uploaded photo |
| `required` | `boolean` | ❌ | Defaults to `true` |

**Widget Interaction Behavior**:
When the user taps "Take Photo" or "Choose from Gallery" on `PhotoRequest`:
1. The widget calls the injected `onPhotoRequest(source, requestType, actionName, targetPath, surfaceId, componentId)` callback.
2. `SellingSessionViewModel` captures a compressed JPEG (`maxWidth: 1280, maxHeight: 1280, imageQuality: 80`) via `ImageCaptureRepository`, writes a non-empty marker/URI to `targetPath` in the surface's `DataModel`, and sends a `ChatMessage.user` containing:
   - `UiInteractionPart.create(jsonEncode({"version": "v0.9", "action": {"name": actionName, "surfaceId": surfaceId, "sourceComponentId": componentId, "timestamp": ..., "context": {"requestType": requestType, "targetPath": targetPath}}}))`
   - `DataPart(imageBytes, mimeType: 'image/jpeg')`

### 3.4 `PriceRange`
Displays the suggested price range bar (`minPrice` — `suggestedPrice` — `maxPrice`), pricing rationale, and an interactive slider / numeric input bound to `selectedPrice`.

| Property | JSON Schema Type | Required | Description |
|---|---|---|---|
| `component` | `"PriceRange"` | ✅ | Discriminator |
| `minPrice` | `DynamicNumber` | ✅ | Lower bound of suggested range |
| `suggestedPrice` | `DynamicNumber` | ✅ | Recommended market price |
| `maxPrice` | `DynamicNumber` | ✅ | Upper bound of suggested range |
| `selectedPrice` | `DynamicNumber` | ✅ | DataBinding `{"path": "/pricing/askingPrice"}` |
| `currency` | `string` | ✅ | ISO 4217 currency code (`"USD"`, `"COP"`) |
| `rationale` | `DynamicString` | ✅ | Explanation of price calculation |

### 3.5 `ListingPreview`
Renders the final marketplace listing preview card with photo carousel, editable/bound title and description, formatted asking price, spec chips, missing-items checklist, and Publish button.

| Property | JSON Schema Type | Required | Description |
|---|---|---|---|
| `component` | `"ListingPreview"` | ✅ | Discriminator |
| `title` | `DynamicString` | ✅ | Bound to `{"path": "/preview/title"}` or literal |
| `description` | `DynamicString` | ✅ | Bound to `{"path": "/preview/description"}` or literal |
| `category` | `"car" \| "motorcycle" \| "phone"` | ✅ | Category badge |
| `price` | `DynamicNumber` | ✅ | Bound to `{"path": "/pricing/askingPrice"}` or literal |
| `currency` | `string` | ✅ | Currency code (`"USD"`, `"COP"`) |
| `imageUrls` | `array<string>` (`minItems: 1`) | ✅ | Uploaded photo URLs |
| `specs` | `array<{label: string, value: DynamicString}>` | ✅ | Key-value specification pills |
| `missingChecklist` | `array<{item: string, completed: boolean}>` | ✅ | Readiness checklist items |
| `publishAction` | `Action` | ✅ | Dispatches `UserActionEvent` (`"publish_listing"`) |

---

## 4. Canonical `DataModel` Paths

| Surface | Path | Type | Description |
|---|---|---|---|
| `selling_step_1_detected` | `/detected/imageUrl` | `string` | URL of initial uploaded item photo |
| `selling_step_1_detected` | `/detected/summary` | `string` | Agent's visual detection summary |
| `selling_step_1_detected` | `/detected/brand` | `string` | Pre-filled brand |
| `selling_step_1_detected` | `/detected/model` | `string` | Pre-filled model |
| `selling_step_1_detected` | `/detected/year` | `string` | Pre-filled year or generation |
| `selling_step_1_detected` | `/detected/color` | `string` | Pre-filled color |
| `selling_step_1_detected` | `/details/mileageKm` | `string` | Vehicle mileage in km (`car`, `motorcycle`) |
| `selling_step_1_detected` | `/details/engineCc` | `string` | Engine displacement in cc (`car` ICE, `motorcycle` ICE) |
| `selling_step_1_detected` | `/details/batteryRangeKm` | `string` | EV full-charge range in km (`isEv: true`) |
| `selling_step_1_detected` | `/details/batteryHealthPct` | `number` | Battery health 1..100 (`phone`, or EV `car`/`motorcycle`) |
| `selling_step_1_detected` | `/details/ownersCount` | `list<string>` | Selected owner count option (`["1"]`, `["2"]`, `["3+"]`) |
| `selling_step_1_detected` | `/details/papersUpToDate` | `boolean` | Registration/inspection papers valid (`car`, `motorcycle`) |
| `selling_step_1_detected` | `/details/storageGb` | `list<string>` | Selected phone storage (`["128"]`, `["256"]`, `["512"]`, `["1024"]`) |
| `selling_step_1_detected` | `/details/unlocked` | `boolean` | Carrier unlocked (`phone`) |
| `selling_step_1_detected` | `/details/hasDamage` | `boolean` | Whether item has visible or functional damage |
| `selling_step_2_followup` | `/followup/odometerPhotoUrl` | `string` | Uploaded odometer photo URL |
| `selling_step_2_followup` | `/followup/damagePhotoUrl` | `string` | Uploaded damage photo URL |
| `selling_step_2_followup` | `/followup/damageNotes` | `string` | User notes describing damage |
| `selling_step_3_preview` | `/pricing/askingPrice` | `number` | User-adjustable asking price |
| `selling_step_3_preview` | `/pricing/rationale` | `string` | Pricing explanation |
| `selling_step_3_preview` | `/preview/title` | `string` | Generated listing title |
| `selling_step_3_preview` | `/preview/description` | `string` | Generated listing description |

---

## 5. Client → Agent Action Contracts (`UserActionEvent`)

All client actions arrive at the Python `SnapSellAgentExecutor` inside an A2A `DataPart`:
```json
{
  "version": "v0.9",
  "action": {
    "name": "<action_name>",
    "surfaceId": "<surface_id>",
    "sourceComponentId": "<component_id>",
    "timestamp": "2026-10-21T00:00:00.000Z",
    "context": { ... }
  }
}
```

| Action `name` | Accompanied by `FilePart`? | `context` Keys | Agent Response |
|---|---|---|---|
| `identify_item` | ✅ Yes (initial item photo JPEG) | `{}` | Calls Gemini Vision + `record_detected_item`; emits `selling_step_1_detected` or `selling_unsupported` |
| `request_odometer_scan` | ❌ No | `{"category": "car" \| "motorcycle"}` | Emits `selling_step_2_followup` with `PhotoRequest(requestType: "odometer")` |
| `submit_detected_details` | ❌ No | `category`, `brand`, `model`, `year`, `color`, plus category-specific `/details/*` values | Calls `validate_listing_fields`; if invalid → updates `selling_step_1_detected` with error text; if follow-up needed (`hasDamage` or missing odometer) → emits `selling_step_2_followup`; otherwise calls `estimate_price_and_build_preview` and emits `selling_step_3_preview` |
| `upload_followup_photo` | ✅ Yes (damage or odometer JPEG) | `{"requestType": "damage" \| "odometer" \| "extra", "targetPath": "..."}` | If `odometer`, runs Gemini Vision OCR + `extract_odometer_reading` and updates `DataModel`; updates `selling_step_2_followup` `previewUrl` |
| `submit_followup` | ❌ No | `{"odometerPhotoUrl": "...", "damagePhotoUrl": "...", "damageNotes": "..."}` | Calls `estimate_price_and_build_preview` and emits `selling_step_3_preview` |
| `publish_listing` | ❌ No | `{"title": "...", "description": "...", "askingPrice": 23400, "currency": "USD", "category": "..."}` | Emits `selling_step_4_published` confirmation surface and sets A2A `TaskState.completed` |
| `start_new_listing` | ❌ No | `{}` | Client resets session and returns to `EntryScreen` |
