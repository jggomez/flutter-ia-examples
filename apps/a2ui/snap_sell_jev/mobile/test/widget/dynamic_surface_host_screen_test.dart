import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:mobile/domain/models/captured_photo.dart';
import 'package:mobile/domain/models/jev_decision.dart';
import 'package:mobile/ui/features/selling/views/dynamic_surface_host_screen.dart';
import 'package:mobile/ui/features/selling/view_models/selling_session_view_model.dart';
import 'package:mobile/ui/providers/repository_providers.dart';

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

    testWidgets('the Jev decisions panel lists what Jev decided and why', (
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
      final List<Object?> step1 = jsonDecode(
        File('../contracts/examples/jev/01_detected_car.json')
            .readAsStringSync(),
      ) as List<Object?>;
      fakeAgent.emitJsonMessages(step1.cast<Map<String, Object?>>());
      fakeAgent.emitDecisions(const <JevDecision>[
        JevDecision(
          stage: 'photo',
          question: 'category',
          answer: 'car',
          probability: 0.76,
          outcome: "stage for 'car'",
        ),
        JevDecision(
          stage: 'form',
          question: 'field_warrantyActive',
          answer: 'yes',
          probability: 0.81,
          outcome: 'field shown',
        ),
        JevDecision(
          stage: 'form',
          question: 'field_ownersCount',
          answer: 'no',
          probability: 0.30,
          outcome: 'field skipped',
        ),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('jev_decisions_button')));
      await tester.pumpAndSettle();

      expect(find.text('Jev decisions'), findsOneWidget);
      expect(find.text('Which questions to ask'), findsOneWidget);
      expect(find.text('warrantyActive'), findsOneWidget);
      expect(find.text('yes · 81%'), findsOneWidget);
      expect(find.text('field shown'), findsOneWidget);
      expect(find.text('field skipped'), findsOneWidget);
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
          File('../contracts/examples/1.0/01_detected_car.json')
              .readAsStringSync(),
        ) as List<Object?>;
        fakeAgent.emitJsonMessages(rawStep1.cast<Map<String, Object?>>());
        await tester.pumpAndSettle();

        expect(find.byType(A2uiSurface), findsOneWidget);
        expect(
          find.textContaining(
            '2021 Mazda CX-30 Grand Touring in Soul Red Crystal',
          ),
          findsOneWidget,
        );

        final List<Object?> rawStep3 = jsonDecode(
          File('../contracts/examples/1.0/04_listing_preview.json')
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
