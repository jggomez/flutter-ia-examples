import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:a2ui_core/a2ui_core.dart' as a2ui_core;
import 'package:genui/genui.dart';

import '../../core/config/app_config.dart';
import '../../domain/repositories/image_capture_repository.dart';
import 'items/detected_item_card_item.dart';
import 'items/listing_preview_item.dart';
import 'items/photo_request_item.dart';
import 'items/price_range_item.dart';
import 'items/snap_sell_button_item.dart';
import 'items/step_progress_item.dart';

/// Builds the hybrid Snap & Sell A2UI v0.9 catalog combining standard basic
/// widgets with the 5 marketplace custom components.
Catalog buildSnapSellCatalog({
  ImageCaptureRepository? imageCaptureService,
  PhotoRequestCaptureCallback? onCapturePhotoRequested,
  Map<String, Uint8List>? localPhotos,
}) {
  return BasicCatalogItems.asCatalog().copyWith(
    catalogId: AppConfig.snapSellCatalogId,
    catalogIdAliases: AppConfig.catalogIdAliases,
    newItems: <CatalogItem>[
      snapSellButtonItem,
      stepProgressItem,
      buildDetectedItemCardCatalogItem(localPhotos: localPhotos),
      buildPhotoRequestCatalogItem(
        imageCaptureService: imageCaptureService,
        onCapturePhotoRequested: onCapturePhotoRequested,
      ),
      priceRangeItem,
      listingPreviewItem,
    ],
  );
}

/// Feeds a list of raw A2UI v0.9 JSON envelopes into a [SurfaceController].
void feedA2uiJson(
  SurfaceController controller,
  List<Map<String, Object?>> messages,
) {
  for (final Map<String, Object?> rawMessage in messages) {
    controller.handleMessage(a2ui_core.A2uiMessage.fromJson(rawMessage));
  }
}
