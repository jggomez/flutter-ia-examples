import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('Contract examples 0.9 rendering', () {
    const List<(String, String)> exampleFiles = <(String, String)>[
      ('01_detected_car.json', 'selling_step_1_detected'),
      ('02_followup_damage_odometer.json', 'selling_step_2_followup'),
      ('03_detected_phone.json', 'selling_step_1_detected'),
      ('04_listing_preview.json', 'selling_step_3_preview'),
      ('05_unsupported_item.json', 'selling_unsupported'),
    ];

    for (final (String fileName, String expectedSurfaceId) in exampleFiles) {
      testWidgets(
        'renders $fileName ($expectedSurfaceId) via SurfaceController.handleMessage without exceptions',
        (WidgetTester tester) async {
          final File file = File('../contracts/examples/0.9/$fileName');
          expect(file.existsSync(), isTrue);

          final List<Object?> rawMessages =
              jsonDecode(file.readAsStringSync()) as List<Object?>;
          final SurfaceController controller = SurfaceController(
            catalogs: <Catalog>[buildSnapSellCatalog()],
          );
          addTearDown(controller.dispose);

          final List<ChatMessage> validationErrors = <ChatMessage>[];
          final sub = controller.onSubmit.listen(validationErrors.add);
          addTearDown(sub.cancel);

          feedA2uiJson(controller, rawMessages.cast<Map<String, Object?>>());

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Surface(
                    surfaceContext: controller.contextFor(expectedSurfaceId),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            validationErrors,
            isEmpty,
            reason:
                'No A2UI schema validation errors should be emitted for $fileName',
          );
          expect(find.byType(Surface), findsOneWidget);
        },
      );
    }
  });
}
