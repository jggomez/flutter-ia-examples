import 'dart:convert';
import 'dart:typed_data';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/widgets.dart';

import '../../core/config/app_config.dart';
import '../../domain/repositories/image_capture_repository.dart';
import 'items/detected_item_card_item.dart';
import 'items/listing_preview_item.dart';
import 'items/photo_request_item.dart';
import 'items/price_range_item.dart';
import 'items/snap_sell_button_item.dart';
import 'items/step_progress_item.dart';
import 'snap_sell_contract.g.dart';

/// The A2UI v1.0 Snap & Sell catalog document shared with the agent
/// (generated from `contracts/snap_sell_catalog.json`).
final Map<String, Object?> snapSellCatalogDocument =
    jsonDecode(snapSellCatalogJson) as Map<String, Object?>;

/// The contract parsed by `a2ui_core`: component and function definitions only.
final CatalogApi snapSellCatalogApi = Catalog.fromJson(
  snapSellCatalogDocument,
  protocolVersion: A2uiProtocolVersion.v1_0,
);

/// Implements contract component [name] with [builder].
///
/// The schema and composition rules (`allowedParents`) come from the contract,
/// so the renderer validates exactly what the agent's Express compiler emits.
ComponentImplementation implementContractComponent(
  String name,
  ComponentWidgetBuilder builder,
) {
  final ComponentApi definition = snapSellCatalogApi.components[name]!;
  return ComponentImplementation(
    name: name,
    schema: definition.schema,
    allowedParents: definition.allowedParents,
    allowedChildren: definition.allowedChildren,
    builder: builder,
  );
}

/// Builds the renderer side of the Snap & Sell catalog.
///
/// One catalog id holds the Basic Catalog subset the contract lists plus the
/// five selling components. `priceFeedback` is deliberately not implemented
/// here: a v1.0 renderer sends a call to a function its catalog lacks to the
/// agent as `callAgentFunction`.
CatalogImplementation buildSnapSellCatalog({
  ImageCaptureRepository? imageCaptureService,
  PhotoRequestCaptureCallback? onCapturePhotoRequested,
  Map<String, Uint8List>? localPhotos,
  OpenUrlCallback? openUrl,
}) {
  return CatalogImplementation(
    id: AppConfig.snapSellCatalogId,
    protocolVersion: A2uiProtocolVersion.v1_0,
    title: snapSellCatalogApi.title,
    description: snapSellCatalogApi.description,
    instructions: snapSellCatalogApi.instructions,
    definitions: BasicComponents.api.definitions,
    components: <ComponentImplementation>[
      BasicComponents.text,
      BasicComponents.image,
      BasicComponents.icon,
      BasicComponents.row,
      BasicComponents.column,
      BasicComponents.card,
      BasicComponents.divider,
      snapSellButtonComponent,
      BasicComponents.textField,
      BasicComponents.checkBox,
      BasicComponents.choicePicker,
      BasicComponents.slider,
      stepProgressComponent,
      buildDetectedItemCardComponent(localPhotos: localPhotos),
      buildPhotoRequestComponent(
        imageCaptureService: imageCaptureService,
        onCapturePhotoRequested: onCapturePhotoRequested,
      ),
      priceRangeComponent,
      listingPreviewComponent,
    ],
    functions: BasicCatalog.v1_0(openUrl: openUrl).functions.values
        .toList(growable: false),
  );
}

/// Helpers for custom components that write data or emit agent-bound actions
/// outside a schema-declared `Action` property.
extension SnapSellNode on ComponentNode<ComponentImplementation> {
  /// Writes [value] at absolute data model [path] of this node's surface.
  void writeData(String path, Object? value) {
    context?.dataContext.set(path, value);
  }

  /// Emits an `action` named [name] with a literal [actionContext].
  Future<void> emitAction(String name, Map<String, Object?> actionContext) {
    return context?.dispatchAction(<String, dynamic>{
          'event': <String, Object?>{'name': name, 'context': actionContext},
        }) ??
        Future<void>.value();
  }
}

/// Keeps a [TextEditingController] in sync with a value the data model owns.
void syncController(TextEditingController controller, String next) {
  if (controller.text == next) return;
  controller.value = controller.value.copyWith(
    text: next,
    selection: TextSelection.collapsed(offset: next.length),
  );
}
