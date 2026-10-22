import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';

void main() {
  group('buildSnapSellCatalog unit tests', () {
    test(
      'creates a Catalog with canonical catalogId and all 5 custom items',
      () {
        final Catalog catalog = buildSnapSellCatalog();
        expect(catalog.catalogId, equals(AppConfig.snapSellCatalogId));
        for (final String alias in AppConfig.catalogIdAliases) {
          expect(catalog.matchesId(alias), isTrue);
        }

        final Set<String> names = catalog.items
            .map((CatalogItem e) => e.name)
            .toSet();
        expect(
          names,
          containsAll(<String>[
            'StepProgress',
            'DetectedItemCard',
            'PhotoRequest',
            'PriceRange',
            'ListingPreview',
          ]),
        );
      },
    );
  });
}
