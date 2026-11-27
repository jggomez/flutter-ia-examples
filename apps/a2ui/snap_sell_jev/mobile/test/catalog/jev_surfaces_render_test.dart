import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/ui/catalog/items/detected_item_card_item.dart';
import 'package:mobile/ui/catalog/items/listing_preview_item.dart';
import 'package:mobile/ui/catalog/items/photo_request_item.dart';
import 'package:mobile/ui/catalog/items/step_progress_item.dart';

import '../support/fakes.dart';

/// Surfaces assembled by the Jev agent's code (`agent/app/surfaces.py`),
/// exported by `agent/scripts/export_jev_surfaces.py`. The renderer cannot
/// tell them apart from LLM-written ones: same catalog, same wire format.
List<Map<String, Object?>> _loadJevSurface(String fileName) {
  final File file = File('../contracts/examples/jev/$fileName');
  return (jsonDecode(file.readAsStringSync()) as List<Object?>)
      .cast<Map<String, Object?>>();
}

void main() {
  const List<(String, String, Type)> surfaces = <(String, String, Type)>[
    ('01_detected_car.json', 'selling_step_1_detected', DetectedItemCardView),
    ('02_detected_ev.json', 'selling_step_1_detected', DetectedItemCardView),
    ('03_detected_phone.json', 'selling_step_1_detected', DetectedItemCardView),
    ('04_followup_damage.json', 'selling_step_2_followup', PhotoRequestCard),
    ('05_listing_preview.json', 'selling_step_3_preview', ListingPreviewCard),
    ('06_published.json', 'selling_step_4_published', StepProgressView),
    ('07_unsupported.json', 'selling_unsupported', Card),
    (
      '08_detected_classic_car.json',
      'selling_step_1_detected',
      DetectedItemCardView,
    ),
    (
      '09_detected_sport_motorcycle.json',
      'selling_step_1_detected',
      DetectedItemCardView,
    ),
  ];

  for (final (String file, String surfaceId, Type keyWidget) in surfaces) {
    testWidgets('Jev-assembled $file renders $surfaceId with no errors', (
      WidgetTester tester,
    ) async {
      final A2uiHarness harness = A2uiHarness();
      addTearDown(harness.dispose);

      harness.feed(_loadJevSurface(file));
      expect(harness.errors.map((e) => e.toJson()), isEmpty);

      await harness.pump(tester, surfaceId);
      expect(tester.takeException(), isNull);
      expect(find.byType(keyWidget), findsWidgets);
      expect(harness.errors.map((e) => e.toJson()), isEmpty);
      for (int i = 0; i < harness.agentCalls.length; i++) {
        harness.answerLastAgentCall('ok');
      }
      await tester.pumpAndSettle();
    });
  }
}
