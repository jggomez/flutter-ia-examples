import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ui/catalog/items/detected_item_card_item.dart';
import 'package:mobile/ui/catalog/items/listing_preview_item.dart';
import 'package:mobile/ui/catalog/items/photo_request_item.dart';
import 'package:mobile/ui/catalog/items/price_range_item.dart';
import 'package:mobile/ui/catalog/items/step_progress_item.dart';

import '../support/fakes.dart';

void main() {
  const List<(String, String, Type)> examples = <(String, String, Type)>[
    ('01_detected_car.json', 'selling_step_1_detected', DetectedItemCardView),
    (
      '02_followup_damage_odometer.json',
      'selling_step_2_followup',
      PhotoRequestCard,
    ),
    ('03_detected_phone.json', 'selling_step_1_detected', DetectedItemCardView),
    ('04_listing_preview.json', 'selling_step_3_preview', ListingPreviewCard),
    ('05_unsupported_item.json', 'selling_unsupported', Card),
  ];

  for (final (String file, String surfaceId, Type keyWidget) in examples) {
    testWidgets('v1.0 example $file renders $surfaceId with no errors', (
      WidgetTester tester,
    ) async {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);

      harness.feed(loadContractExample(file));
      expect(harness.errors.map((e) => e.toJson()), isEmpty);

      await harness.pump(tester, surfaceId);
      expect(tester.takeException(), isNull);
      expect(find.byType(keyWidget), findsWidgets);
      if (surfaceId != 'selling_unsupported') {
        expect(find.byType(StepProgressView), findsOneWidget);
      }
      expect(harness.errors.map((e) => e.toJson()), isEmpty);
      // Settle pending agent calls (PriceRange.feedback) so no timer leaks.
      for (int i = 0; i < harness.agentCalls.length; i++) {
        harness.answerLastAgentCall('ok');
      }
      await tester.pumpAndSettle();
    });
  }

  testWidgets('04 PriceRange asks the agent for priceFeedback and shows it', (
    WidgetTester tester,
  ) async {
    final A2uiHarness harness = A2uiHarness();
    addTearDown(harness.dispose);
    harness.feed(loadContractExample('04_listing_preview.json'));
    await harness.pump(tester, 'selling_step_3_preview');

    expect(find.byType(PriceRangeCard), findsOneWidget);
    expect(harness.agentCalls, isNotEmpty);
    final Map<String, Object?> call = harness.agentCalls.last.callFunction;
    expect(call['@call'], 'priceFeedback');
    expect(
      (call['args'] as Map<String, Object?>).keys,
      contains('askingPrice'),
    );

    harness.answerLastAgentCall('Right on the suggested price: competitive.');
    await tester.pumpAndSettle();
    expect(
      find.text('Right on the suggested price: competitive.'),
      findsOneWidget,
    );
  });
}
