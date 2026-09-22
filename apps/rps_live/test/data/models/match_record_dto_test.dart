import 'package:flutter_test/flutter_test.dart';
import 'package:rps_live/data/models/match_record_dto.dart';
import 'package:rps_live/domain/models/match_record.dart';
import 'package:rps_live/domain/models/move.dart';
import 'package:rps_live/domain/models/round_outcome.dart';

void main() {
  test('fromDomain <-> toDomain round-trips every field', () {
    final playedAt = DateTime(2026, 9, 20, 12, 30);
    final record = MatchRecord(
      id: 'round-1',
      playedAt: playedAt,
      playerMove: Move.scissors,
      aiMove: Move.paper,
      outcome: RoundOutcome.win,
    );

    final dto = MatchRecordDto.fromDomain(record);

    expect(dto.id, 'round-1');
    expect(dto.playedAtMillisSinceEpoch, playedAt.millisecondsSinceEpoch);
    expect(dto.playerMoveIndex, Move.scissors.index);
    expect(dto.aiMoveIndex, Move.paper.index);
    expect(dto.outcomeIndex, RoundOutcome.win.index);

    final roundTripped = dto.toDomain();
    expect(roundTripped.id, record.id);
    expect(roundTripped.playedAt, playedAt);
    expect(roundTripped.playerMove, Move.scissors);
    expect(roundTripped.aiMove, Move.paper);
    expect(roundTripped.outcome, RoundOutcome.win);
  });

  test('round-trips every Move/RoundOutcome combination', () {
    for (final playerMove in Move.values) {
      for (final aiMove in Move.values) {
        for (final outcome in RoundOutcome.values) {
          final record = MatchRecord(
            id: 'id',
            playedAt: DateTime(2026),
            playerMove: playerMove,
            aiMove: aiMove,
            outcome: outcome,
          );
          final roundTripped = MatchRecordDto.fromDomain(record).toDomain();
          expect(roundTripped.playerMove, playerMove);
          expect(roundTripped.aiMove, aiMove);
          expect(roundTripped.outcome, outcome);
        }
      }
    }
  });
}
