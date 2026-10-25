import 'package:hive/hive.dart';

import '../../domain/models/study_document.dart';
import '../local/hive_boxes.dart';

/// Hive-persisted DTO for an imported and indexed [StudyDocument].
///
/// Also persists [chunkIds] so `DocumentIngestionRepositoryImpl.deleteDocument`
/// can remove all corresponding vector chunks from `RagIndex` without scanning
/// the entire vector table.
class StudyDocumentDto {
  StudyDocumentDto({
    required this.id,
    required this.title,
    required this.fileName,
    required this.filePath,
    required this.pageCount,
    required this.chunkCount,
    required this.indexedAtMillis,
    List<String> chunkIds = const [],
  }) : chunkIds = List<String>.unmodifiable(chunkIds);

  final String id;
  final String title;
  final String fileName;
  final String filePath;
  final int pageCount;
  final int chunkCount;
  final int indexedAtMillis;
  final List<String> chunkIds;

  factory StudyDocumentDto.fromDomain(
    StudyDocument document, {
    List<String> chunkIds = const [],
  }) {
    return StudyDocumentDto(
      id: document.id,
      title: document.title,
      fileName: document.fileName,
      filePath: document.filePath,
      pageCount: document.pageCount,
      chunkCount: document.chunkCount,
      indexedAtMillis: document.indexedAt.millisecondsSinceEpoch,
      chunkIds: chunkIds,
    );
  }

  StudyDocument toDomain() {
    return StudyDocument(
      id: id,
      title: title,
      fileName: fileName,
      filePath: filePath,
      pageCount: pageCount,
      chunkCount: chunkCount,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(indexedAtMillis),
    );
  }
}

/// Manual Hive [TypeAdapter] for [StudyDocumentDto] (`typeId: 0`).
class StudyDocumentDtoAdapter extends TypeAdapter<StudyDocumentDto> {
  @override
  final int typeId = HiveTypeIds.studyDocumentDto;

  @override
  StudyDocumentDto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, Object?>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StudyDocumentDto(
      id: fields[0] as String,
      title: fields[1] as String,
      fileName: fields[2] as String,
      filePath: fields[3] as String,
      pageCount: fields[4] as int,
      chunkCount: fields[5] as int,
      indexedAtMillis: fields[6] as int,
      chunkIds: (fields[7] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  void write(BinaryWriter writer, StudyDocumentDto obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.fileName)
      ..writeByte(3)
      ..write(obj.filePath)
      ..writeByte(4)
      ..write(obj.pageCount)
      ..writeByte(5)
      ..write(obj.chunkCount)
      ..writeByte(6)
      ..write(obj.indexedAtMillis)
      ..writeByte(7)
      ..write(obj.chunkIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudyDocumentDtoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
