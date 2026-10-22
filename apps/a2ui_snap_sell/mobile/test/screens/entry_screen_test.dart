import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/domain/models/captured_photo.dart';
import 'package:mobile/src/screens/entry_screen.dart';
import 'package:mobile/ui/features/selling/view_models/selling_session_view_model.dart';
import 'package:mobile/ui/providers/repository_providers.dart';

import '../support/fakes.dart';

void main() {
  group('EntryScreen widget tests', () {
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
      'renders "¿Qué quieres vender?", category chips, and triggers camera capture',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
              sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
            ],
            child: const MaterialApp(home: EntryScreen()),
          ),
        );

        expect(find.text('¿Qué quieres vender?'), findsOneWidget);
        expect(find.text('Cars'), findsOneWidget);
        expect(find.text('Motorcycles'), findsOneWidget);
        expect(find.text('Phones'), findsOneWidget);
        expect(find.text('Take Photo'), findsOneWidget);
        expect(find.text('Choose from Gallery'), findsOneWidget);

        await tester.tap(find.text('Take Photo'));
        await tester.pump();

        expect(
          fakeCapture.capturedSources,
          equals(<PhotoCaptureSource>[PhotoCaptureSource.camera]),
        );
        expect(fakeAgent.startedPhotos, hasLength(1));
      },
    );

    testWidgets('triggers gallery capture when Choose from Gallery is tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
            sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
          ],
          child: const MaterialApp(home: EntryScreen()),
        ),
      );

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();

      expect(
        fakeCapture.capturedSources,
        equals(<PhotoCaptureSource>[PhotoCaptureSource.gallery]),
      );
      expect(fakeAgent.startedPhotos, hasLength(1));
    });

    testWidgets(
      'shows CircularProgressIndicator on buttons when isBusy is true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imageCaptureRepositoryProvider.overrideWithValue(fakeCapture),
              sellingAgentRepositoryProvider.overrideWithValue(fakeAgent),
            ],
            child: const MaterialApp(home: EntryScreen()),
          ),
        );

        final BuildContext context = tester.element(find.byType(EntryScreen));
        final ProviderContainer container = ProviderScope.containerOf(context);

        // Trigger capture without immediately completing to keep session busy
        container
            .read(sellingSessionViewModelProvider.notifier)
            .startSessionWithPhoto(PhotoCaptureSource.camera);
        await tester.pump();

        // Expect at least one CircularProgressIndicator replacing the button icons
        expect(find.byType(CircularProgressIndicator), findsWidgets);
      },
    );
  });
}
