import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';
import 'package:mobile/ui/catalog/widgets/price_range_card.dart';

void main() {
  group('PriceRangeCard widget tests', () {
    testWidgets('renders cleanly on narrow width (320px) without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final SurfaceController controller = SurfaceController(
        catalogs: <Catalog>[buildSnapSellCatalog()],
      );
      addTearDown(controller.dispose);

      feedA2uiJson(controller, <Map<String, Object?>>[
        <String, Object?>{
          'version': 'v0.9',
          'createSurface': <String, Object?>{
            'surfaceId': 'test_surface',
            'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
            'sendDataModel': true,
          },
        },
      ]);

      final DataContext dataContext = DataContext(
        controller.contextFor('test_surface').dataModel,
        DataPath('/'),
      );
      final ValueNotifier<num?> selectedPriceNotifier = ValueNotifier<num?>(
        1800,
      );
      final ValueNotifier<String?> rationaleNotifier = ValueNotifier<String?>(
        'Fair market value',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: PriceRangeCard(
                  minPrice: 1200,
                  suggestedPrice: 1800,
                  maxPrice: 2500,
                  currency: 'USD',
                  boundPath: '/pricing/askingPrice',
                  literalSelectedPrice: null,
                  selectedPriceNotifier: selectedPriceNotifier,
                  rationaleNotifier: rationaleNotifier,
                  dataContext: dataContext,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Suggested Price Range'), findsOneWidget);
      expect(find.text('Suggested: USD 1,800'), findsOneWidget);
      expect(find.text('Min: USD 1,200'), findsOneWidget);
      expect(find.text('USD 1,800'), findsOneWidget);
      expect(find.text('Max: USD 2,500'), findsOneWidget);
    });
  });
}
