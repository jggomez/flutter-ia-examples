import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/repositories/classifier_repository.dart';
import 'package:rps_live/ui/features/vs_ai/views/vs_ai_screen.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

const _rockResult = ClassificationResult(
  paperConfidence: 0.05,
  rockConfidence: 0.9,
  scissorsConfidence: 0.05,
);

Future<void> _pumpVsAiScreen(
  WidgetTester tester, {
  required FakeClassifierRepository classifier,
  required FakeHistoryRepository history,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        classifierRepositoryProvider.overrideWithValue(classifier),
        historyRepositoryProvider.overrideWithValue(history),
      ],
      child: const MaterialApp(home: VsAiScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the idle prompt and a disabled scoreboard at 0-0-0', (
    tester,
  ) async {
    await _pumpVsAiScreen(
      tester,
      classifier: FakeClassifierRepository(),
      history: FakeHistoryRepository(),
    );

    expect(find.text('Tú vs. IA'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Empezar ronda'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3)); // wins, losses, ties
  });

  testWidgets('tapping "Empezar ronda" runs the countdown then shows the '
      'result', (tester) async {
    final classifier = FakeClassifierRepository();
    await _pumpVsAiScreen(
      tester,
      classifier: classifier,
      history: FakeHistoryRepository(),
    );
    classifier.emit(_rockResult);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('startRoundButton')));
    await tester.pump(); // enter countdown

    expect(find.byKey(const ValueKey('countdownValue')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // 3 countdown ticks at the production 1-second cadence.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(); // let the reveal/result state settle

    expect(find.byKey(const ValueKey('roundOutcome')), findsOneWidget);
    expect(find.textContaining('Jugar de nuevo'), findsOneWidget);
  });

  testWidgets('shows an error banner when the camera/model fails to '
      'initialize', (tester) async {
    final classifier = FakeClassifierRepository()
      ..initializeError = const CameraUnavailableException(
        'Camera unavailable (test)',
      );
    await _pumpVsAiScreen(
      tester,
      classifier: classifier,
      history: FakeHistoryRepository(),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('vsAiErrorBanner')), findsOneWidget);
  });

  testWidgets('displays CameraViewfinder with live gesture badge and '
      'switches camera when switchCameraButton is tapped', (tester) async {
    final classifier = FakeClassifierRepository();
    await _pumpVsAiScreen(
      tester,
      classifier: classifier,
      history: FakeHistoryRepository(),
    );
    await tester.pump();

    classifier.emit(_rockResult);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('cameraViewfinder')), findsOneWidget);
    expect(find.textContaining('Piedra'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('switchCameraButton')));
    await tester.pump();

    expect(classifier.switchCameraCallCount, 1);
  });
}
