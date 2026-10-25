import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rag_study_gemma/data/local/hive_boxes.dart';
import 'package:rag_study_gemma/data/models/chat_message_dto.dart';
import 'package:rag_study_gemma/data/repositories/chat_history_repository_impl.dart';
import 'package:rag_study_gemma/domain/models/chat_message.dart';
import 'package:rag_study_gemma/domain/models/chat_role.dart';
import 'package:rag_study_gemma/domain/models/citation.dart';

void main() {
  group('ChatHistoryRepositoryImpl', () {
    late Directory tempDir;
    late Box<ChatMessageDto> box;
    late ChatHistoryRepositoryImpl repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('chat_hist_repo_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(HiveTypeIds.chatMessageDto)) {
        Hive.registerAdapter(ChatMessageDtoAdapter());
      }
      box = await Hive.openBox<ChatMessageDto>(HiveBoxes.chatHistory);
      repository = ChatHistoryRepositoryImpl(box: box);
    });

    tearDown(() async {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'append, getAll (sorted chronologically), and clear work end-to-end',
      () async {
        final msg2 = ChatMessage(
          id: 'm2',
          role: ChatRole.assistant,
          text: 'Answer with citation [Book, p. 2].',
          createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
          citations: const [
            Citation(
              id: 'c1',
              docId: 'd1',
              docTitle: 'Book',
              pageNumber: 2,
              snippet: 'Excerpt on page 2',
              similarityScore: 0.85,
            ),
          ],
        );
        final msg1 = ChatMessage(
          id: 'm1',
          role: ChatRole.user,
          text: 'Question?',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        );

        await repository.append(msg2);
        await repository.append(msg1);

        final loaded = await repository.getAll();
        expect(loaded, equals([msg1, msg2]));

        await repository.clear();
        expect(await repository.getAll(), isEmpty);
      },
    );
  });
}
