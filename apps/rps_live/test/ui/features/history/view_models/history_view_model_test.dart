import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/repositories/history_repository.dart';
import 'package:rps_live/ui/features/history/view_models/history_view_model.dart';
import 'package:rps_live/ui/providers/repository_providers.dart';

import '../../../../support/fakes.dart';

MatchRecord _record(String id) => MatchRecord(
  id: id,
  playedAt: DateTime(2026, 1, 1),
  playerMove: Move.rock,
  aiMove: Move.scissors,
  outcome: RoundOutcome.win,
);

void main() {
  group('HistoryViewModel', () {
    test('loads all persisted records from HistoryRepository', () async {
      final history = FakeHistoryRepository(seed: [_record('a'), _record('b')]);
      final container = ProviderContainer(
        overrides: [historyRepositoryProvider.overrideWithValue(history)],
      );
      addTearDown(container.dispose);

      final records = await container.read(historyViewModelProvider.future);

      expect(records.map((r) => r.id).toList(), ['a', 'b']);
    });

    test('surfaces a load failure as AsyncError', () async {
      final history = FakeHistoryRepository()
        ..getAllError = const HistoryPersistenceException('box not open');
      final container = ProviderContainer(
        overrides: [historyRepositoryProvider.overrideWithValue(history)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(historyViewModelProvider.future),
        throwsA(isA<HistoryPersistenceException>()),
      );
    });

    test('refresh() re-reads the repository', () async {
      final history = FakeHistoryRepository(seed: [_record('a')]);
      final container = ProviderContainer(
        overrides: [historyRepositoryProvider.overrideWithValue(history)],
      );
      addTearDown(container.dispose);

      await container.read(historyViewModelProvider.future);
      await history.add(_record('b'));
      await container.read(historyViewModelProvider.notifier).refresh();

      final records = container.read(historyViewModelProvider).requireValue;
      expect(records.map((r) => r.id).toList(), ['a', 'b']);
    });
  });
}
