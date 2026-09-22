import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/repositories/history_repository.dart';
import 'package:rps_live/ui/features/history/views/history_screen.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

MatchRecord _record(String id, RoundOutcome outcome) => MatchRecord(
  id: id,
  playedAt: DateTime(2026, 1, 1),
  playerMove: Move.rock,
  aiMove: Move.scissors,
  outcome: outcome,
);

Future<void> _pumpHistoryScreen(
  WidgetTester tester,
  FakeHistoryRepository history,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [historyRepositoryProvider.overrideWithValue(history)],
      child: const MaterialApp(home: HistoryScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows an empty state when no rounds have been played', (
    tester,
  ) async {
    await _pumpHistoryScreen(tester, FakeHistoryRepository());

    expect(find.byKey(const ValueKey('historyEmpty')), findsOneWidget);
  });

  testWidgets('lists persisted rounds with an aggregate stats summary', (
    tester,
  ) async {
    final history = FakeHistoryRepository(
      seed: [
        _record('r1', RoundOutcome.win),
        _record('r2', RoundOutcome.lose),
        _record('r3', RoundOutcome.tie),
      ],
    );
    await _pumpHistoryScreen(tester, history);

    expect(find.byKey(const ValueKey('historyItem_r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('historyItem_r2')), findsOneWidget);
    expect(find.byKey(const ValueKey('historyItem_r3')), findsOneWidget);
    expect(find.text('1V - 1D - 1E (3 rondas)'), findsOneWidget);
  });

  testWidgets('shows an error message when the history fails to load', (
    tester,
  ) async {
    final history = FakeHistoryRepository()
      ..getAllError = const HistoryPersistenceException('box not open');
    await _pumpHistoryScreen(tester, history);

    expect(find.byKey(const ValueKey('historyError')), findsOneWidget);
  });
}
