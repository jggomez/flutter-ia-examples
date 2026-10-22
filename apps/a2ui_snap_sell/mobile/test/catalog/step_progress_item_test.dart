import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';

void main() {
  group('StepProgress catalog widget', () {
    late SurfaceController controller;

    setUp(() {
      controller = SurfaceController(
        catalogs: <Catalog>[buildSnapSellCatalog()],
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('renders currentStep of totalSteps, stepLabels, and subtitle', (
      WidgetTester tester,
    ) async {
      feedA2uiJson(controller, <Map<String, Object?>>[
        <String, Object?>{
          'version': 'v0.9',
          'createSurface': <String, Object?>{
            'surfaceId': 'test_surface',
            'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
          },
        },
        <String, Object?>{
          'version': 'v0.9',
          'updateComponents': <String, Object?>{
            'surfaceId': 'test_surface',
            'components': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'root',
                'component': 'StepProgress',
                'currentStep': 2,
                'totalSteps': 4,
                'stepLabels': <String>[
                  'Detected',
                  'Follow-up',
                  'Preview',
                  'Published',
                ],
                'subtitle': 'Provide follow-up photos for accuracy.',
              },
            ],
          },
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Surface(
              surfaceContext: controller.contextFor('test_surface'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Step 2 of 4'), findsOneWidget);
      expect(find.text('Detected'), findsOneWidget);
      expect(find.text('Follow-up'), findsWidgets);
      expect(find.text('Preview'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(
        find.text('Provide follow-up photos for accuracy.'),
        findsOneWidget,
      );
    });
  });
}
