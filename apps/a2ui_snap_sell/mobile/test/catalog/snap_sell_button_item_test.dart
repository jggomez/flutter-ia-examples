import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('SnapSellButton catalog widget', () {
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
      'renders child text, and upon tap enters loading state with spinner, disables itself, and dispatches action',
      (WidgetTester tester) async {
        final List<ChatMessage> submitted = <ChatMessage>[];
        final subscription = controller.onSubmit.listen(submitted.add);
        addTearDown(subscription.cancel);

        feedA2uiJson(controller, <Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'step_test',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
              'sendDataModel': true,
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateComponents': <String, Object?>{
              'surfaceId': 'step_test',
              'components': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'Button',
                  'variant': 'primary',
                  'child': 'btn_label',
                  'action': <String, Object?>{
                    'event': <String, Object?>{
                      'name': 'submit_detected_details',
                      'context': <String, Object?>{'brand': 'Mazda'},
                    },
                  },
                },
                <String, Object?>{
                  'id': 'btn_label',
                  'component': 'Text',
                  'text': 'Continuar',
                },
              ],
            },
          },
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Surface(surfaceContext: controller.contextFor('step_test')),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Continuar'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        final Finder buttonFinder = find.byType(ElevatedButton);
        expect(buttonFinder, findsOneWidget);
        final ElevatedButton elevatedBtnBefore = tester.widget<ElevatedButton>(
          buttonFinder,
        );
        expect(elevatedBtnBefore.onPressed, isNotNull);

        // Tap the button
        await tester.tap(buttonFinder);
        await tester.pump();

        // After tap: loading spinner appears inside button and button is disabled
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Continuar'), findsOneWidget);

        final ElevatedButton elevatedBtnAfter = tester.widget<ElevatedButton>(
          buttonFinder,
        );
        expect(
          elevatedBtnAfter.onPressed,
          isNull,
          reason: 'Button must be disabled while in loading state to prevent double taps',
        );

        // Action was dispatched
        expect(submitted, hasLength(1));
        final Map<String, Object?> payload = jsonDecode(
          submitted.first.parts.uiInteractionParts.first.interaction,
        ) as Map<String, Object?>;
        final Map<String, Object?> action =
            payload['action'] as Map<String, Object?>;
        expect(action['name'], equals('submit_detected_details'));
        expect(
          (action['context'] as Map<String, Object?>)['brand'],
          equals('Mazda'),
        );

        // Second tap does nothing because onPressed is null
        await tester.tap(buttonFinder);
        await tester.pump();
        expect(submitted, hasLength(1));
      },
    );

    testWidgets('borderless button shows spinner and disables when tapped', (
      WidgetTester tester,
    ) async {
      final List<ChatMessage> submitted = <ChatMessage>[];
      final subscription = controller.onSubmit.listen(submitted.add);
      addTearDown(subscription.cancel);

      feedA2uiJson(controller, <Map<String, Object?>>[
        <String, Object?>{
          'version': 'v0.9',
          'createSurface': <String, Object?>{
            'surfaceId': 'borderless_test',
            'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
            'sendDataModel': true,
          },
        },
        <String, Object?>{
          'version': 'v0.9',
          'updateComponents': <String, Object?>{
            'surfaceId': 'borderless_test',
            'components': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'root',
                'component': 'Button',
                'variant': 'borderless',
                'child': 'borderless_label',
                'action': <String, Object?>{
                  'event': <String, Object?>{
                    'name': 'request_odometer_scan',
                    'context': <String, Object?>{},
                  },
                },
              },
              <String, Object?>{
                'id': 'borderless_label',
                'component': 'Text',
                'text': 'Or scan odometer photo',
              },
            ],
          },
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Surface(
              surfaceContext: controller.contextFor('borderless_test'),
            ),
          ),
        ),
      );
      await tester.pump();

      final Finder textButtonFinder = find.byType(TextButton);
      expect(textButtonFinder, findsOneWidget);
      expect(tester.widget<TextButton>(textButtonFinder).onPressed, isNotNull);

      await tester.tap(textButtonFinder);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<TextButton>(textButtonFinder).onPressed, isNull);
      expect(submitted, hasLength(1));
    });
  });
}
