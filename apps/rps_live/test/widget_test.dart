// App-level smoke test: confirms the app boots under a ProviderScope with
// fake repositories (no real camera, interpreter, or Hive box needed) and
// the three feature tabs are reachable from the bottom navigation bar.
//
// Per-feature behavior is covered by the widget tests under
// `test/ui/features/*/views/`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rps_live/app.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('App boots on the "Tú vs. IA" tab and can navigate to the '
      'other two tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          classifierRepositoryProvider.overrideWithValue(
            FakeClassifierRepository(),
          ),
          historyRepositoryProvider.overrideWithValue(FakeHistoryRepository()),
        ],
        child: const RpsLiveApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Tú vs. IA'), findsWidgets); // app bar + nav destination
    expect(find.widgetWithText(FilledButton, 'Empezar ronda'), findsOneWidget);

    await tester.tap(find.text('Práctica'));
    await tester.pump();
    expect(find.text('Práctica libre'), findsOneWidget);

    await tester.tap(find.text('Historial'));
    await tester.pump();
    expect(find.text('Historial'), findsWidgets); // app bar + nav destination
  });
}
