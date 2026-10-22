import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('ListingPreview catalog widget', () {
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
      'renders title, price, specs, checklist icons, and dispatches publishAction and editAction',
      (WidgetTester tester) async {
        final List<ChatMessage> submitted = <ChatMessage>[];
        final subscription = controller.onSubmit.listen(submitted.add);
        addTearDown(subscription.cancel);

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
                'pricing': <String, Object?>{'askingPrice': 23400},
                'preview': <String, Object?>{
                  'title': '2021 Mazda CX-30 Grand Touring',
                  'description': 'Clean single-owner SUV.',
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
                  'component': 'ListingPreview',
                  'title': <String, Object?>{'path': '/preview/title'},
                  'description': <String, Object?>{
                    'path': '/preview/description',
                  },
                  'category': 'car',
                  'price': <String, Object?>{'path': '/pricing/askingPrice'},
                  'currency': 'USD',
                  'imageUrls': <String>['local://car.jpg'],
                  'specs': <Map<String, Object?>>[
                    <String, Object?>{'label': 'Year', 'value': '2021'},
                    <String, Object?>{'label': 'Mileage', 'value': '34,200 km'},
                  ],
                  'missingChecklist': <Map<String, Object?>>[
                    <String, Object?>{
                      'item': 'Main photo uploaded',
                      'completed': true,
                    },
                    <String, Object?>{
                      'item': 'Odometer verified',
                      'completed': false,
                    },
                  ],
                  'canPublish': true,
                  'publishAction': <String, Object?>{
                    'event': <String, Object?>{
                      'name': 'publish_listing',
                      'context': <String, Object?>{
                        'askingPrice': <String, Object?>{
                          'path': '/pricing/askingPrice',
                        },
                      },
                    },
                  },
                  'editAction': <String, Object?>{
                    'event': <String, Object?>{
                      'name': 'edit_details',
                      'context': <String, Object?>{},
                    },
                  },
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

        expect(find.text('2021 Mazda CX-30 Grand Touring'), findsOneWidget);
        expect(find.text('Clean single-owner SUV.'), findsOneWidget);
        expect(find.text('34,200 km'), findsOneWidget);
        expect(find.text('Main photo uploaded'), findsOneWidget);
        expect(find.text('Odometer verified'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

        await tester.tap(find.text('Publish Listing'));
        await tester.pump();

        expect(submitted, hasLength(1));
        final Map<String, Object?> publishPayload = jsonDecode(
          submitted.first.parts.uiInteractionParts.first.interaction,
        ) as Map<String, Object?>;
        final Map<String, Object?> publishEvent =
            publishPayload['action'] as Map<String, Object?>;
        expect(publishEvent['name'], equals('publish_listing'));
        expect(
          (publishEvent['context'] as Map<String, Object?>)['askingPrice'],
          equals(23400),
        );

        await tester.tap(find.text('Edit Details'));
        await tester.pump();
        expect(submitted, hasLength(2));
        final Map<String, Object?> editPayload = jsonDecode(
          submitted.last.parts.uiInteractionParts.first.interaction,
        ) as Map<String, Object?>;
        final Map<String, Object?> editEvent =
            editPayload['action'] as Map<String, Object?>;
        expect(editEvent['name'], equals('edit_details'));
      },
    );

    testWidgets(
      'tapping Publish Listing shows loading spinner, disables button, and prevents double submission',
      (WidgetTester tester) async {
        final List<ChatMessage> submitted = <ChatMessage>[];
        final subscription = controller.onSubmit.listen(submitted.add);
        addTearDown(subscription.cancel);

        feedA2uiJson(controller, <Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'step_3_loading',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
              'sendDataModel': true,
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateComponents': <String, Object?>{
              'surfaceId': 'step_3_loading',
              'components': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'ListingPreview',
                  'title': 'Test Item',
                  'description': 'Description',
                  'category': 'car',
                  'price': 10000,
                  'currency': 'USD',
                  'imageUrls': <String>[],
                  'specs': <Map<String, Object?>>[],
                  'missingChecklist': <Map<String, Object?>>[],
                  'canPublish': true,
                  'publishAction': <String, Object?>{
                    'event': <String, Object?>{
                      'name': 'publish_listing',
                      'context': <String, Object?>{},
                    },
                  },
                },
              ],
            },
          },
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Surface(
                  surfaceContext: controller.contextFor('step_3_loading'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Finder publishBtnFinder = find.widgetWithText(
          FilledButton,
          'Publish Listing',
        );
        expect(publishBtnFinder, findsOneWidget);
        expect(
          tester.widget<FilledButton>(publishBtnFinder).onPressed,
          isNotNull,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.tap(publishBtnFinder);
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.widget<FilledButton>(publishBtnFinder).onPressed, isNull);
        expect(submitted, hasLength(1));

        // Second tap does nothing
        await tester.tap(publishBtnFinder);
        await tester.pump();
        expect(submitted, hasLength(1));
      },
    );
  });
}
