import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('DetectedItemCard catalog widget', () {
    late SurfaceController controller;

    setUp(() {
      controller = SurfaceController(
        catalogs: <Catalog>[
          buildSnapSellCatalog(
            localPhotos: <String, Uint8List>{
              'local://initial': _kTransparentPng,
            },
          ),
        ],
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'renders category badge, confidence percentage, summary, EV badge, and two-way bound fields',
      (WidgetTester tester) async {
        feedA2uiJson(controller, <Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'step_1',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
              'sendDataModel': true,
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateDataModel': <String, Object?>{
              'surfaceId': 'step_1',
              'path': '/',
              'value': <String, Object?>{
                'detected': <String, Object?>{
                  'imageUrl': 'local://initial',
                  'summary': '2023 Tesla Model 3 in Pearl White',
                  'brand': 'Tesla',
                  'model': 'Model 3',
                },
                'draft': <String, Object?>{
                  'year': '2023',
                  'color': 'Pearl White',
                },
              },
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateComponents': <String, Object?>{
              'surfaceId': 'step_1',
              'components': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'DetectedItemCard',
                  'category': 'car',
                  'imageUrl': <String, Object?>{'path': '/detected/imageUrl'},
                  'confidence': 0.94,
                  'summary': <String, Object?>{'path': '/detected/summary'},
                  'isEv': true,
                  'fields': <Map<String, Object?>>[
                    <String, Object?>{
                      'key': 'brand',
                      'label': 'Brand',
                      'value': <String, Object?>{'path': '/detected/brand'},
                      'editable': true,
                    },
                    <String, Object?>{
                      'key': 'year',
                      'label': 'Year',
                      'value': <String, Object?>{'path': '/draft/year'},
                      'editable': true,
                    },
                  ],
                },
              ],
            },
          },
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Surface(surfaceContext: controller.contextFor('step_1')),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.textContaining('94%'), findsOneWidget);
        expect(find.textContaining('CAR'), findsOneWidget);
        expect(find.textContaining('EV'), findsOneWidget);
        expect(find.text('2023 Tesla Model 3 in Pearl White'), findsOneWidget);

        final Finder brandField = find.widgetWithText(TextField, 'Brand');
        expect(brandField, findsOneWidget);
        await tester.enterText(brandField, 'Rivian');
        await tester.pump();

        final DataModel dataModel = controller.contextFor('step_1').dataModel;
        expect(
          dataModel.getValue<String>(DataPath('/detected/brand')),
          equals('Rivian'),
        );

        final Finder yearField = find.widgetWithText(TextField, 'Year');
        await tester.enterText(yearField, '2024');
        await tester.pump();
        expect(
          dataModel.getValue<String>(DataPath('/draft/year')),
          equals('2024'),
        );
      },
    );
  });
}

final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
