import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rps_live/data/local/hive_boxes.dart';
import 'package:rps_live/data/models/match_record_dto.dart';
import 'package:rps_live/data/repositories/history_repository_impl.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';
import 'package:rps_live/domain/repositories/history_repository.dart';

MatchRecord _record(
  String id, {
  required DateTime playedAt,
  RoundOutcome outcome = RoundOutcome.win,
}) => MatchRecord(
  id: id,
  playedAt: playedAt,
  playerMove: Move.rock,
  aiMove: Move.scissors,
  outcome: outcome,
);

void main() {
  // In-memory Hive: `Hive.init` against a temp directory involves no
  // platform channel, so this runs in a plain VM `flutter test` process
  // with no real device/emulator (see doc/adr/0002-persistence-hive.md).
  late Box<MatchRecordDto> box;
  late HistoryRepository repository;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('rps_live_hive_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(HiveTypeIds.matchRecordDto)) {
      Hive.registerAdapter(MatchRecordDtoAdapter());
    }
    final boxName = tempDir.path.split(Platform.pathSeparator).last;
    box = await Hive.openBox<MatchRecordDto>(boxName);
    repository = HistoryRepositoryImpl(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test(
    'getAll returns an empty list when nothing has been persisted',
    () async {
      expect(await repository.getAll(), isEmpty);
    },
  );

  test('add persists a record retrievable via getAll', () async {
    final record = _record('r1', playedAt: DateTime(2026, 1, 1));

    await repository.add(record);
    final all = await repository.getAll();

    expect(all, hasLength(1));
    expect(all.single.id, 'r1');
    expect(all.single.outcome, RoundOutcome.win);
  });

  test('getAll returns records most recent first', () async {
    await repository.add(_record('oldest', playedAt: DateTime(2026, 1, 1)));
    await repository.add(_record('newest', playedAt: DateTime(2026, 3, 1)));
    await repository.add(_record('middle', playedAt: DateTime(2026, 2, 1)));

    final all = await repository.getAll();

    expect(all.map((r) => r.id).toList(), ['newest', 'middle', 'oldest']);
  });

  test('clear removes all persisted records', () async {
    await repository.add(_record('r1', playedAt: DateTime(2026, 1, 1)));
    await repository.add(_record('r2', playedAt: DateTime(2026, 1, 2)));

    await repository.clear();

    expect(await repository.getAll(), isEmpty);
  });

  test('survives being re-opened against the same box (persists across '
      '"restarts")', () async {
    await repository.add(_record('r1', playedAt: DateTime(2026, 1, 1)));
    final boxName = box.name;
    await box.close();

    final reopened = await Hive.openBox<MatchRecordDto>(boxName);
    final reopenedRepository = HistoryRepositoryImpl(box: reopened);

    expect((await reopenedRepository.getAll()).single.id, 'r1');
    box = reopened;
  });
}
