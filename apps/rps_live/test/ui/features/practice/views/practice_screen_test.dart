import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/classification_result.dart';
import 'package:rps_live/domain/repositories/classifier_repository.dart';
import 'package:rps_live/ui/features/practice/views/practice_screen.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

const _result = ClassificationResult(
  paperConfidence: 0.6,
  rockConfidence: 0.3,
  scissorsConfidence: 0.1,
);

Future<void> _pumpPracticeScreen(
  WidgetTester tester,
  FakeClassifierRepository classifier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [classifierRepositoryProvider.overrideWithValue(classifier)],
      child: const MaterialApp(home: PracticeScreen()),
    ),
  );
}

void main() {
  testWidgets('shows a loading indicator before the first classification '
      'arrives', (tester) async {
    await _pumpPracticeScreen(tester, FakeClassifierRepository());

    expect(find.byKey(const ValueKey('practiceLoading')), findsOneWidget);
  });

  testWidgets('renders a confidence meter per move once classified', (
    tester,
  ) async {
    final classifier = FakeClassifierRepository();
    await _pumpPracticeScreen(tester, classifier);
    classifier.emit(_result);
    await tester.pump();

    expect(find.text('Papel'), findsOneWidget);
    expect(find.text('Piedra'), findsOneWidget);
    expect(find.text('Tijera'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.byKey(const ValueKey('confidenceMeter_paper')), findsOneWidget);
  });

  testWidgets('shows an error message when the camera/model fails', (
    tester,
  ) async {
    final classifier = FakeClassifierRepository()
      ..initializeError = const ModelAssetNotFoundException(
        'rps_model.tflite is missing.',
      );
    await _pumpPracticeScreen(tester, classifier);
    await tester.pump();

    expect(find.byKey(const ValueKey('practiceError')), findsOneWidget);
    expect(find.textContaining('rps_model.tflite is missing.'), findsOneWidget);
  });

  testWidgets('renders CameraViewfinder and switches camera on button tap', (
    tester,
  ) async {
    final classifier = FakeClassifierRepository();
    await _pumpPracticeScreen(tester, classifier);
    classifier.emit(_result);
    await tester.pump();

    expect(find.byKey(const ValueKey('cameraViewfinder')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('switchCameraButton')));
    await tester.pump();

    expect(classifier.switchCameraCallCount, 1);
  });
}
