import 'package:hive/hive.dart';

import '../../domain/models/chat_message.dart';
import '../../domain/models/chat_role.dart';
import '../../domain/models/citation.dart';
import '../local/hive_boxes.dart';

/// Serialized representation of a [Citation] inside [ChatMessageDto].
class CitationDto {
  const CitationDto({
    required this.id,
    required this.docId,
    required this.docTitle,
    required this.pageNumber,
    required this.snippet,
    required this.similarityScore,
  });

  final String id;
  final String docId;
  final String docTitle;
  final int pageNumber;
  final String snippet;
  final double similarityScore;

  factory CitationDto.fromDomain(Citation citation) {
    return CitationDto(
      id: citation.id,
      docId: citation.docId,
      docTitle: citation.docTitle,
      pageNumber: citation.pageNumber,
      snippet: citation.snippet,
      similarityScore: citation.similarityScore,
    );
  }

  factory CitationDto.fromMap(Map<Object?, Object?> map) {
    return CitationDto(
      id: (map['id'] as String?) ?? '',
      docId: (map['docId'] as String?) ?? '',
      docTitle: (map['docTitle'] as String?) ?? '',
      pageNumber: (map['pageNumber'] as num?)?.toInt() ?? 1,
      snippet: (map['snippet'] as String?) ?? '',
      similarityScore: (map['similarityScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, Object> toMap() => {
    'id': id,
    'docId': docId,
    'docTitle': docTitle,
    'pageNumber': pageNumber,
    'snippet': snippet,
    'similarityScore': similarityScore,
  };

  Citation toDomain() {
    return Citation(
      id: id,
      docId: docId,
      docTitle: docTitle,
      pageNumber: pageNumber,
      snippet: snippet,
      similarityScore: similarityScore,
    );
  }
}

/// Hive-persisted DTO for a [ChatMessage] including source [Citation] metadata.
class ChatMessageDto {
  ChatMessageDto({
    required this.id,
    required this.roleIndex,
    required this.text,
    required this.createdAtMillis,
    List<CitationDto> citations = const [],
  }) : citations = List<CitationDto>.unmodifiable(citations);

  final String id;
  final int roleIndex;
  final String text;
  final int createdAtMillis;
  final List<CitationDto> citations;

  factory ChatMessageDto.fromDomain(ChatMessage message) {
    return ChatMessageDto(
      id: message.id,
      roleIndex: message.role.index,
      text: message.text,
      createdAtMillis: message.createdAt.millisecondsSinceEpoch,
      citations: [for (final c in message.citations) CitationDto.fromDomain(c)],
    );
  }

  ChatMessage toDomain() {
    final safeRoleIndex = roleIndex.clamp(0, ChatRole.values.length - 1);
    return ChatMessage(
      id: id,
      role: ChatRole.values[safeRoleIndex],
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      citations: [for (final c in citations) c.toDomain()],
      isStreaming: false,
    );
  }
}

/// Manual Hive [TypeAdapter] for [ChatMessageDto] (`typeId: 1`).
class ChatMessageDtoAdapter extends TypeAdapter<ChatMessageDto> {
  @override
  final int typeId = HiveTypeIds.chatMessageDto;

  @override
  ChatMessageDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, Object?>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    final rawCitations = (fields[4] as List?) ?? const [];
    return ChatMessageDto(
      id: fields[0] as String,
      roleIndex: fields[1] as int,
      text: fields[2] as String,
      createdAtMillis: fields[3] as int,
      citations: [
        for (final item in rawCitations)
          if (item is Map) CitationDto.fromMap(item),
      ],
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
      ..write(obj.createdAtMillis)
      ..writeByte(4)
      ..write([for (final c in obj.citations) c.toMap()]);
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
