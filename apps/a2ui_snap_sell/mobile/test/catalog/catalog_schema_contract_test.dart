import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('SnapSellCatalog contract parity', () {
    late Map<String, Object?> contractJson;
    late Catalog catalog;

    setUpAll(() {
      final File contractFile = File('../contracts/snap_sell_catalog.json');
      expect(
        contractFile.existsSync(),
        isTrue,
        reason: 'Shared contract file ../contracts/snap_sell_catalog.json must exist',
      );
      contractJson =
          jsonDecode(contractFile.readAsStringSync()) as Map<String, Object?>;
      catalog = buildSnapSellCatalog();
    });

    test('registers canonical catalogId and aliases from contract', () {
      expect(
        catalog.catalogId,
        equals(
          'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
        ),
      );
      expect(catalog.catalogId, equals(contractJson['catalogId']));
      expect(
        catalog.matchesId(
          'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
        ),
        isTrue,
      );
      expect(
        catalog.matchesId(
          'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json',
        ),
        isTrue,
      );
    });

    test('registers all 12 basic components and all 5 custom components', () {
      final Map<String, Object?> contractComponents =
          contractJson['components'] as Map<String, Object?>;
      final Set<String> registeredNames = catalog.items
          .map((CatalogItem item) => item.name)
          .toSet();

      for (final String componentName in contractComponents.keys) {
        expect(
          registeredNames,
          contains(componentName),
          reason: 'Catalog is missing component "$componentName" from contract',
        );
      }
    });

    for (final String customName in <String>[
      'StepProgress',
      'DetectedItemCard',
      'PhotoRequest',
      'PriceRange',
      'ListingPreview',
    ]) {
      test(
        '$customName matches required and defined schema properties in snap_sell_catalog.json',
        () {
          final Map<String, Object?> contractComponents =
              contractJson['components'] as Map<String, Object?>;
          final Map<String, Object?> componentDef =
              contractComponents[customName] as Map<String, Object?>;
          final List<Object?> allOf = componentDef['allOf'] as List<Object?>;
          final Map<String, Object?> propsBlock =
              allOf.last as Map<String, Object?>;
          final Map<String, Object?> expectedProps =
              propsBlock['properties'] as Map<String, Object?>;
          final List<String> expectedRequired =
              (propsBlock['required'] as List<Object?>).cast<String>();

          final CatalogItem item = catalog.items.firstWhere(
            (CatalogItem i) => i.name == customName,
          );
          final Map<String, Object?> actualSchema = item.dataSchema.value;
          final Map<String, Object?> actualProps =
              actualSchema['properties'] as Map<String, Object?>;
          final List<String> actualRequired =
              (actualSchema['required'] as List<Object?>).cast<String>();

          expect(
            actualRequired.toSet(),
            equals(expectedRequired.toSet()),
            reason: 'Required properties mismatch for $customName',
          );
          expect(
            actualProps.keys.toSet(),
            containsAll(expectedProps.keys),
            reason: 'Defined properties mismatch for $customName',
          );
        },
      );
    }
  });
}
