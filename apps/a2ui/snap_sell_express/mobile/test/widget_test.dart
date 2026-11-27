import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/ui/providers/repository_providers.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'SnapSellApp navigates from EntryScreen to DynamicSurfaceHostScreen and resets cleanly',
    (WidgetTester tester) async {
      final FakeImageCaptureService fakeCapture = FakeImageCaptureService();
      final FakeA2uiAgentService fakeAgent = FakeA2uiAgentService(
        imageCaptureService: fakeCapture,
      );
      addTearDown(fakeAgent.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
            sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
          ],
          child: const SnapSellApp(),
        ),
      );

      expect(find.text('¿Qué quieres vender?'), findsOneWidget);

      await tester.tap(find.text('Take Photo'));
      await tester.pump();

      expect(find.byTooltip('Start Over'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(find.text('¿Qué quieres vender?'), findsOneWidget);
    },
  );
}
