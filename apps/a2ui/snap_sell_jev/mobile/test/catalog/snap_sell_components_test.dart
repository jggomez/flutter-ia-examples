import 'dart:convert';
import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/ui/catalog/items/detected_item_card_item.dart';
import 'package:mobile/ui/catalog/items/photo_request_item.dart';
import 'package:mobile/ui/catalog/items/price_range_item.dart';
import 'package:mobile/ui/catalog/items/snap_sell_button_item.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';

import '../support/fakes.dart';

Map<String, Object?> _text(String id, String text) => <String, Object?>{
  'id': id,
  'component': 'Text',
  'text': text,
};

void main() {
  group('contract', () {
    test(
      'embedded catalog is identical to contracts/snap_sell_catalog.json',
      () {
        final Object? onDisk = jsonDecode(
          File('../contracts/snap_sell_catalog.json').readAsStringSync(),
        );
        expect(snapSellCatalogDocument, onDisk);
        expect(snapSellCatalogApi.id, AppConfig.snapSellCatalogId);
      },
    );

    test('renderer implements every contract component, with its rules', () {
      final CatalogImplementation catalog = buildSnapSellCatalog();
      expect(
        catalog.components.keys.toSet(),
        snapSellCatalogApi.components.keys.toSet(),
      );
      expect(catalog.components['StepProgress']!.allowedParents, <String>[
        'Column',
      ]);
    });

    test('priceFeedback is an agent function, not a renderer function', () {
      expect(snapSellCatalogApi.functions.keys, contains('priceFeedback'));
      expect(
        buildSnapSellCatalog().functions.keys,
        isNot(contains('priceFeedback')),
      );
    });

    test('a StepProgress outside a Column is rejected (allowedParents)', () {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);
      harness.feed(<Map<String, Object?>>[
        createSurface('s', <Map<String, Object?>>[
          <String, Object?>{'id': 'root', 'component': 'Card', 'child': 'sp'},
          <String, Object?>{
            'id': 'sp',
            'component': 'StepProgress',
            'currentStep': 1,
            'totalSteps': 4,
            'stepLabels': <String>['A', 'B', 'C', 'D'],
          },
        ]),
      ]);
      expect(harness.errors, isNotEmpty);
    });
  });

  group('components', () {
    testWidgets('Button: @checks disable it; tap sends resolved action', (
      WidgetTester tester,
    ) async {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);
      harness.feed(<Map<String, Object?>>[
        createSurface(
          'form',
          <Map<String, Object?>>[
            <String, Object?>{
              'id': 'root',
              'component': 'Column',
              'children': <String>['field', 'btn'],
            },
            <String, Object?>{
              'id': 'field',
              'component': 'TextField',
              'label': 'Brand',
              'value': <String, Object?>{'@path': '/brand'},
            },
            <String, Object?>{
              'id': 'btn',
              'component': 'Button',
              'variant': 'primary',
              'child': 'lbl',
              '@checks': <Object?>[
                <String, Object?>{
                  'condition': <String, Object?>{
                    '@call': 'required',
                    'args': <String, Object?>{
                      'value': <String, Object?>{'@path': '/brand'},
                    },
                  },
                  'message': 'Brand is required',
                },
              ],
              'action': <String, Object?>{
                'event': <String, Object?>{
                  'name': 'submit_detected_details',
                  'context': <String, Object?>{
                    'brand': <String, Object?>{'@path': '/brand'},
                  },
                },
              },
            },
            _text('lbl', 'Continue'),
          ],
          dataModel: <String, Object?>{'brand': ''},
        ),
      ]);
      await harness.pump(tester, 'form');

      ElevatedButton button() =>
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(find.byType(SnapSellButton), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Mazda');
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(harness.actions, hasLength(1));
      final A2uiRendererAction action = harness.actions.single.action;
      expect(action.name, 'submit_detected_details');
      expect(action.surfaceId, 'form');
      expect(action.context, <String, Object?>{'brand': 'Mazda'});
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('DetectedItemCard: editing a field writes its bound path', (
      WidgetTester tester,
    ) async {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);
      harness.feed(loadContractExample('01_detected_car.json'));
      await harness.pump(tester, 'selling_step_1_detected');

      final Finder brand = find.descendant(
        of: find.byType(DetectedItemCardView),
        matching: find.widgetWithText(TextField, 'Brand'),
      );
      expect(find.text('Mazda'), findsWidgets);
      await tester.enterText(brand, 'Toyota');
      await tester.pumpAndSettle();
      expect(
        harness.data('selling_step_1_detected', '/detected/brand'),
        'Toyota',
      );
    });

    testWidgets(
      'PriceRange: committed price triggers a new priceFeedback call',
      (WidgetTester tester) async {
        final A2uiHarness harness = A2uiHarness();
        addTearDown(harness.dispose);
        harness.feed(loadContractExample('04_listing_preview.json'));
        await harness.pump(tester, 'selling_step_3_preview');
        harness.answerLastAgentCall('first');
        await tester.pumpAndSettle();
        final int callsBefore = harness.agentCalls.length;

        final Finder priceField = find.descendant(
          of: find.byType(PriceRangeCard),
          matching: find.byType(TextField),
        );
        await tester.enterText(priceField, '19000');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          harness.data('selling_step_3_preview', '/pricing/askingPrice'),
          19000,
        );
        expect(harness.agentCalls.length, greaterThan(callsBefore));
        final Map<String, Object?> args =
            harness.agentCalls.last.callFunction['args']!
                as Map<String, Object?>;
        expect(args['askingPrice'], 19000);

        harness.answerLastAgentCall('Below market: likely to sell fast.');
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        expect(find.text('Below market: likely to sell fast.'), findsOneWidget);
      },
    );

    testWidgets('PhotoRequest: capture queues the photo and emits the action', (
      WidgetTester tester,
    ) async {
      final FakeImageCaptureService capture = FakeImageCaptureService();
      final A2uiHarness harness = A2uiHarness(
        catalog: buildSnapSellCatalog(imageCaptureService: capture),
      );
      addTearDown(harness.dispose);
      harness.feed(loadContractExample('02_followup_damage_odometer.json'));
      await harness.pump(tester, 'selling_step_2_followup');

      final PhotoRequestCard first = tester.widget<PhotoRequestCard>(
        find.byType(PhotoRequestCard).first,
      );
      await tester.tap(find.text('Take Photo').first);
      await tester.pumpAndSettle();

      expect(capture.queuedFollowupPhotos, hasLength(1));
      expect(harness.actions, hasLength(1));
      final A2uiRendererAction action = harness.actions.single.action;
      expect(action.name, first.actionName);
      expect(action.context['status'], 'uploaded');
      expect(
        harness.data('selling_step_2_followup', first.targetPath),
        'uploaded',
      );
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('ListingPreview: publish emits publish_listing', (
      WidgetTester tester,
    ) async {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);
      harness.feed(loadContractExample('04_listing_preview.json'));
      await harness.pump(tester, 'selling_step_3_preview');
      harness.answerLastAgentCall('ok');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Publish Listing'));
      await tester.tap(find.text('Publish Listing'));
      await tester.pump();
      expect(harness.actions.map((ActionMessage a) => a.action.name), <String>[
        'publish_listing',
      ]);
    });
  });

  test('formatPriceNumber groups thousands', () {
    expect(formatPriceNumber(23400), '23,400');
    expect(formatPriceNumber(1234567.6), '1,234,568');
    expect(formatPriceNumber(-950), '-950');
  });
}
