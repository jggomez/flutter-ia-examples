// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'match_record_dto.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MatchRecordDtoAdapter extends TypeAdapter<MatchRecordDto> {
  @override
  final int typeId = 0;

  @override
  MatchRecordDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MatchRecordDto(
      id: fields[0] as String,
      playedAtMillisSinceEpoch: fields[1] as int,
      playerMoveIndex: fields[2] as int,
      aiMoveIndex: fields[3] as int,
      outcomeIndex: fields[4] as int,
    );
  }

  @override
  void write(BinaryWriter writer, MatchRecordDto obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.playedAtMillisSinceEpoch)
      ..writeByte(2)
      ..write(obj.playerMoveIndex)
      ..writeByte(3)
      ..write(obj.aiMoveIndex)
      ..writeByte(4)
      ..write(obj.outcomeIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchRecordDtoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
