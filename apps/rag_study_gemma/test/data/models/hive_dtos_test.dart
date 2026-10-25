import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rag_study_gemma/data/local/hive_boxes.dart';
import 'package:rag_study_gemma/data/models/chat_message_dto.dart';
import 'package:rag_study_gemma/data/models/study_document_dto.dart';
import 'package:rag_study_gemma/domain/models/chat_message.dart';
import 'package:rag_study_gemma/domain/models/chat_role.dart';
import 'package:rag_study_gemma/domain/models/citation.dart';
import 'package:rag_study_gemma/domain/models/study_document.dart';

void main() {
  group('HiveBoxes and HiveTypeIds', () {
    test('exposes canonical box names and non-colliding type IDs', () {
      expect(HiveBoxes.documents, equals('study_documents'));
      expect(HiveBoxes.chatHistory, equals('study_chat_history'));
      expect(HiveTypeIds.studyDocumentDto, equals(0));
      expect(HiveTypeIds.chatMessageDto, equals(1));
      expect(
        HiveTypeIds.studyDocumentDto,
        isNot(equals(HiveTypeIds.chatMessageDto)),
      );
    });
  });

  group('StudyDocumentDto & StudyDocumentDtoAdapter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('study_doc_dto_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(HiveTypeIds.studyDocumentDto)) {
        Hive.registerAdapter(StudyDocumentDtoAdapter());
      }
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('converts between StudyDocument domain model and DTO', () {
      final doc = StudyDocument(
        id: 'doc_1',
        title: 'Deep Learning Chapter 4',
        fileName: 'dl_ch4.pdf',
        filePath: '/storage/dl_ch4.pdf',
        pageCount: 18,
        chunkCount: 42,
        indexedAt: DateTime.fromMillisecondsSinceEpoch(1761340800000),
      );
      final dto = StudyDocumentDto.fromDomain(
        doc,
        chunkIds: const ['doc_1_p1_c0', 'doc_1_p1_c1'],
      );

      expect(dto.id, equals('doc_1'));
      expect(dto.title, equals('Deep Learning Chapter 4'));
      expect(dto.fileName, equals('dl_ch4.pdf'));
      expect(dto.filePath, equals('/storage/dl_ch4.pdf'));
      expect(dto.pageCount, equals(18));
      expect(dto.chunkCount, equals(42));
      expect(dto.indexedAtMillis, equals(1761340800000));
      expect(dto.chunkIds, equals(['doc_1_p1_c0', 'doc_1_p1_c1']));

      final restored = dto.toDomain();
      expect(restored, equals(doc));
    });

    test(
      'persists and reads StudyDocumentDto through Hive binary adapter',
      () async {
        final box = await Hive.openBox<StudyDocumentDto>(HiveBoxes.documents);
        final dto = StudyDocumentDto(
          id: 'doc_hive',
          title: 'Linear Algebra Notes',
          fileName: 'linalg.pdf',
          filePath: '/docs/linalg.pdf',
          pageCount: 10,
          chunkCount: 25,
          indexedAtMillis: 1761340900000,
          chunkIds: const ['doc_hive_p1_c0', 'doc_hive_p2_c0'],
        );

        await box.put(dto.id, dto);
        await box.close();

        final reopened = await Hive.openBox<StudyDocumentDto>(
          HiveBoxes.documents,
        );
        final loaded = reopened.get('doc_hive');
        expect(loaded, isNotNull);
        expect(loaded!.id, equals(dto.id));
        expect(loaded.title, equals(dto.title));
        expect(loaded.fileName, equals(dto.fileName));
        expect(loaded.filePath, equals(dto.filePath));
        expect(loaded.pageCount, equals(dto.pageCount));
        expect(loaded.chunkCount, equals(dto.chunkCount));
        expect(loaded.indexedAtMillis, equals(dto.indexedAtMillis));
        expect(loaded.chunkIds, equals(['doc_hive_p1_c0', 'doc_hive_p2_c0']));
      },
    );
  });

  group('ChatMessageDto & ChatMessageDtoAdapter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chat_msg_dto_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(HiveTypeIds.chatMessageDto)) {
        Hive.registerAdapter(ChatMessageDtoAdapter());
      }
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'converts between ChatMessage domain model and DTO with citations',
      () {
        final message = ChatMessage(
          id: 'msg_1',
          role: ChatRole.assistant,
          text: 'Backpropagation computes the gradient [Deep Learning, p. 3].',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1761341000000),
          isStreaming: true,
          citations: const [
            Citation(
              id: 'doc_1_p3_c0',
              docId: 'doc_1',
              docTitle: 'Deep Learning',
              pageNumber: 3,
              snippet: 'The chain rule of calculus is applied...',
              similarityScore: 0.89,
            ),
          ],
        );

        final dto = ChatMessageDto.fromDomain(message);
        expect(dto.id, equals('msg_1'));
        expect(dto.roleIndex, equals(ChatRole.assistant.index));
        expect(dto.text, equals(message.text));
        expect(dto.createdAtMillis, equals(1761341000000));
        expect(dto.citations, hasLength(1));

        final restored = dto.toDomain();
        expect(restored.id, equals(message.id));
        expect(restored.role, equals(ChatRole.assistant));
        expect(restored.text, equals(message.text));
        expect(restored.createdAt, equals(message.createdAt));
        expect(restored.isStreaming, isFalse);
        expect(restored.citations, equals(message.citations));
      },
    );

    test(
      'persists and reads ChatMessageDto through Hive binary adapter',
      () async {
        final box = await Hive.openBox<ChatMessageDto>(HiveBoxes.chatHistory);
        final original = ChatMessage(
          id: 'msg_persisted',
          role: ChatRole.assistant,
          text: 'Eigenvalues satisfy Av = lambda v [Linear Algebra, p. 7].',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1761341200000),
          citations: const [
            Citation(
              id: 'doc_2_p7_c1',
              docId: 'doc_2',
              docTitle: 'Linear Algebra',
              pageNumber: 7,
              snippet:
                  'An eigenvector of a square matrix A is a nonzero vector v.',
              similarityScore: 0.92,
            ),
          ],
        );

        await box.put(original.id, ChatMessageDto.fromDomain(original));
        await box.close();

        final reopened = await Hive.openBox<ChatMessageDto>(
          HiveBoxes.chatHistory,
        );
        final loadedDto = reopened.get('msg_persisted');
        expect(loadedDto, isNotNull);
        final restored = loadedDto!.toDomain();
        expect(restored, equals(original));
      },
    );
  });
}
