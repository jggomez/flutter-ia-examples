import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/domain/models/captured_photo.dart';
import 'package:mobile/src/screens/selling_flow_screen.dart';
import 'package:mobile/src/session/selling_session_controller.dart';

import '../support/fakes.dart';

void main() {
  group('SellingFlowScreen / DynamicSurfaceHostScreen widget tests', () {
    late FakeImageCaptureService fakeCapture;
    late FakeA2uiAgentService fakeAgent;

    setUp(() {
      fakeCapture = FakeImageCaptureService();
      fakeAgent = FakeA2uiAgentService(imageCaptureService: fakeCapture);
    });

    tearDown(() {
      fakeAgent.dispose();
    });

    testWidgets(
      'displays loading indicator while analyzing and renders active A2UI Surface when surfaceUpdates arrive',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
              sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
            ],
            child: const MaterialApp(home: SellingFlowScreen()),
          ),
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SellingFlowScreen)),
        );
        final SellingSessionController controller = container.read(
          sellingSessionControllerProvider.notifier,
        );

        await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
        await tester.pump();

        expect(
          find.textContaining('Analyzing item with Gemini'),
          findsOneWidget,
        );

        final List<Object?> rawStep1 = jsonDecode(
          File('../contracts/examples/0.9/01_detected_car.json')
              .readAsStringSync(),
        ) as List<Object?>;
        fakeAgent.emitJsonMessages(rawStep1.cast<Map<String, Object?>>());
        await tester.pumpAndSettle();

        expect(find.byType(Surface), findsOneWidget);
        expect(
          find.textContaining(
            '2021 Mazda CX-30 Grand Touring in Soul Red Crystal',
          ),
          findsOneWidget,
        );

        final List<Object?> rawStep3 = jsonDecode(
          File('../contracts/examples/0.9/04_listing_preview.json')
              .readAsStringSync(),
        ) as List<Object?>;
        fakeAgent.emitJsonMessages(rawStep3.cast<Map<String, Object?>>());
        await tester.pumpAndSettle();

        expect(find.text('Publish Listing'), findsOneWidget);
      },
    );

    testWidgets('shows error banner when agent emits transport error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
            sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
          ],
          child: const MaterialApp(home: SellingFlowScreen()),
        ),
      );

      fakeAgent.emitError('Connection refused');
      await tester.pump();

      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    testWidgets(
      'renders loading overlay with Procesando and blocks pointer while isProcessing is true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
              sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
            ],
            child: const MaterialApp(home: SellingFlowScreen()),
          ),
        );

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SellingFlowScreen)),
        );
        final SellingSessionController controller = container.read(
          sellingSessionControllerProvider.notifier,
        );

        await controller.startSessionWithPhoto(PhotoCaptureSource.camera);
        await tester.pump();

        expect(find.text('Procesando...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        final Finder ignorePointerFinder = find.byKey(
          const Key('surface_host_ignore_pointer'),
        );
        expect(ignorePointerFinder, findsOneWidget);
        final IgnorePointer ignorePointer = tester.widget<IgnorePointer>(
          ignorePointerFinder,
        );
        expect(ignorePointer.ignoring, isTrue);
      },
    );
  });
}
