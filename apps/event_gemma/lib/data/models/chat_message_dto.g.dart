// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message_dto.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatMessageDtoAdapter extends TypeAdapter<ChatMessageDto> {
  @override
  final int typeId = 0;

  @override
  ChatMessageDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessageDto(
      id: fields[0] as String,
      roleIndex: fields[1] as int,
      text: fields[2] as String,
      createdAtMillisSinceEpoch: fields[3] as int,
      citedTalkIds: (fields[4] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessageDto obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roleIndex)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAtMillisSinceEpoch)
      ..writeByte(4)
      ..write(obj.citedTalkIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageDtoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
