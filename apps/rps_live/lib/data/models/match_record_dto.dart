import 'package:hive/hive.dart';

import '../../domain/models/match_record.dart';
import '../../domain/models/move.dart';
import '../../domain/models/round_outcome.dart';
import '../local/hive_boxes.dart';

part 'match_record_dto.g.dart';

/// Hive-persisted shape for a [MatchRecord].
///
/// Kept as a separate type from the domain [MatchRecord] on purpose: the
/// domain layer must never import `package:hive`, and this DTO is free to
/// evolve its on-disk shape (schema versioning, added fields) independently
/// via `HistoryRepositoryImpl`'s mapping functions.
@HiveType(typeId: HiveTypeIds.matchRecordDto)
class MatchRecordDto {
  const MatchRecordDto({
    required this.id,
    required this.playedAtMillisSinceEpoch,
    required this.playerMoveIndex,
    required this.aiMoveIndex,
    required this.outcomeIndex,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final int playedAtMillisSinceEpoch;

  /// `Move.values[playerMoveIndex]`.
  @HiveField(2)
  final int playerMoveIndex;

  /// `Move.values[aiMoveIndex]`.
  @HiveField(3)
  final int aiMoveIndex;

  /// `RoundOutcome.values[outcomeIndex]`.
  @HiveField(4)
  final int outcomeIndex;

  factory MatchRecordDto.fromDomain(MatchRecord record) => MatchRecordDto(
    id: record.id,
    playedAtMillisSinceEpoch: record.playedAt.millisecondsSinceEpoch,
    playerMoveIndex: record.playerMove.index,
    aiMoveIndex: record.aiMove.index,
    outcomeIndex: record.outcome.index,
  );

  MatchRecord toDomain() => MatchRecord(
    id: id,
    playedAt: DateTime.fromMillisecondsSinceEpoch(playedAtMillisSinceEpoch),
    playerMove: Move.values[playerMoveIndex],
    aiMove: Move.values[aiMoveIndex],
    outcome: RoundOutcome.values[outcomeIndex],
  );
}
