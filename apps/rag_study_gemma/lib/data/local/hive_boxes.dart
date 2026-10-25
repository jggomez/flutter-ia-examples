/// Hive box name registry for StudyGemma.
///
/// Centralized so box names are never duplicated across repositories, tests,
/// and application startup (`Hive.openBox`).
abstract final class HiveBoxes {
  static const String documents = 'study_documents';
  static const String chatHistory = 'study_chat_history';
}

/// Hive `typeId` registry for StudyGemma.
///
/// - 0: `StudyDocumentDto` (`lib/data/models/study_document_dto.dart`)
/// - 1: `ChatMessageDto` (`lib/data/models/chat_message_dto.dart`)
abstract final class HiveTypeIds {
  static const int studyDocumentDto = 0;
  static const int studyDocument = studyDocumentDto;

  static const int chatMessageDto = 1;
  static const int chatMessage = chatMessageDto;
}
