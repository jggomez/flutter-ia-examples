import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('PriceRange catalog widget', () {
    late SurfaceController controller;

    setUp(() {
      controller = SurfaceController(
        catalogs: <Catalog>[buildSnapSellCatalog()],
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'renders price band, suggestedPrice, currency, rationale, and binds Slider/input two-way',
      (WidgetTester tester) async {
        feedA2uiJson(controller, <Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'step_3',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
              'sendDataModel': true,
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateDataModel': <String, Object?>{
              'surfaceId': 'step_3',
              'path': '/',
              'value': <String, Object?>{
                'pricing': <String, Object?>{
                  'askingPrice': 23400,
                  'rationale': 'Low mileage single-owner vehicle.',
                },
              },
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateComponents': <String, Object?>{
              'surfaceId': 'step_3',
              'components': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'PriceRange',
                  'minPrice': 21000,
                  'suggestedPrice': 23400,
                  'maxPrice': 25000,
                  'selectedPrice': <String, Object?>{
                    'path': '/pricing/askingPrice',
                  },
                  'currency': 'USD',
                  'rationale': <String, Object?>{'path': '/pricing/rationale'},
                },
              ],
            },
          },
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Surface(surfaceContext: controller.contextFor('step_3')),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('21,000'), findsOneWidget);
        expect(find.textContaining('23,400'), findsWidgets);
        expect(find.textContaining('25,000'), findsOneWidget);
        expect(find.text('Low mileage single-owner vehicle.'), findsOneWidget);

        final Finder priceField = find.byType(TextField);
        expect(priceField, findsOneWidget);
        await tester.enterText(priceField, '24100');
        await tester.pump();

        final DataModel dataModel = controller.contextFor('step_3').dataModel;
        expect(
          dataModel.getValue<num>(DataPath('/pricing/askingPrice')),
          equals(24100),
        );
      },
    );

    testWidgets('does not overflow on narrow screens (320px logical width)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      feedA2uiJson(controller, <Map<String, Object?>>[
        <String, Object?>{
          'version': 'v0.9',
          'createSurface': <String, Object?>{
            'surfaceId': 'step_3_narrow',
            'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
            'sendDataModel': true,
          },
        },
        <String, Object?>{
          'version': 'v0.9',
          'updateDataModel': <String, Object?>{
            'surfaceId': 'step_3_narrow',
            'path': '/',
            'value': <String, Object?>{
              'pricing': <String, Object?>{'askingPrice': 1800},
            },
          },
        },
        <String, Object?>{
          'version': 'v0.9',
          'updateComponents': <String, Object?>{
            'surfaceId': 'step_3_narrow',
            'components': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'root',
                'component': 'PriceRange',
                'minPrice': 1200,
                'suggestedPrice': 1800,
                'maxPrice': 2500,
                'selectedPrice': <String, Object?>{
                  'path': '/pricing/askingPrice',
                },
                'currency': 'USD',
              },
            ],
          },
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Surface(
                  surfaceContext: controller.contextFor('step_3_narrow'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
