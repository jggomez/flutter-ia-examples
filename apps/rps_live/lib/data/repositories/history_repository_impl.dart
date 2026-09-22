import 'package:hive/hive.dart';

import '../../domain/models/match_record.dart';
import '../../domain/repositories/history_repository.dart';
import '../models/match_record_dto.dart';

/// [HistoryRepository] backed by a Hive `Box<MatchRecordDto>`
/// (see `doc/adr/0002-persistence-hive.md`).
///
/// The [Box] is injected rather than opened internally so tests can pass an
/// in-memory Hive box (`Hive.init` with a temp dir, no platform channels
/// involved) or a fake implementing the same narrow surface — no real
/// device/emulator required.
class HistoryRepositoryImpl implements HistoryRepository {
  // Not `this._box`: a leading underscore in a named-parameter name makes
  // it library-private, which would break `main.dart`'s (a different
  // library) ability to pass it by name.
  // ignore: prefer_initializing_formals
  HistoryRepositoryImpl({required Box<MatchRecordDto> box}) : _box = box;

  final Box<MatchRecordDto> _box;

  @override
  Future<List<MatchRecord>> getAll() async {
    try {
      final records = _box.values.map((dto) => dto.toDomain()).toList()
        // Most recent first, per the HistoryRepository contract.
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
      return records;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HistoryPersistenceException(
          'Failed to read match history from Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> add(MatchRecord record) async {
    try {
      await _box.put(record.id, MatchRecordDto.fromDomain(record));
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HistoryPersistenceException(
          'Failed to persist match record ${record.id} to Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _box.clear();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        HistoryPersistenceException(
          'Failed to clear match history in Hive.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }
}
