import 'dart:io';

import 'package:event_llm_wiki/data/local/hive_boxes.dart';
import 'package:event_llm_wiki/data/models/chat_message_dto.dart';
import 'package:event_llm_wiki/data/repositories/chat_history_repository_impl.dart';
import 'package:event_llm_wiki/domain/models/chat_message.dart';
import 'package:event_llm_wiki/domain/models/chat_role.dart';
import 'package:event_llm_wiki/domain/models/citation.dart';
import 'package:event_llm_wiki/domain/models/conference_day.dart';
import 'package:event_llm_wiki/domain/models/conference_track.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/domain/repositories/chat_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../support/fakes.dart';

Talk _talk(String id, {String title = 'A talk'}) => Talk(
  id: id,
  title: title,
  abstract: 'An abstract.',
  speakers: const [],
  day: ConferenceDay.dayOne,
  track: ConferenceTrack.engineering,
  startTime: DateTime(2026, 11, 10, 9),
  durationMinutes: 30,
);

ChatMessage _message(
  String id, {
  ChatRole role = ChatRole.user,
  String text = 'hello',
  DateTime? createdAt,
  List<Citation> citations = const [],
}) => ChatMessage(
  id: id,
  role: role,
  text: text,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  citations: citations,
);

void main() {
  // Real tempdir Hive box: `Hive.init` against a temp directory involves no
  // platform channel, so this runs in a plain VM `flutter test` process —
  // see doc/adr/0004-persistence-hive-chat-history.md.
  late Box<ChatMessageDto> box;
  late ChatHistoryRepository repository;
  late FakeAgendaRepository agendaRepository;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp(
      'event_llm_wiki_hive_test',
    );
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(HiveTypeIds.chatMessageDto)) {
      Hive.registerAdapter(ChatMessageDtoAdapter());
    }
    final boxName = tempDir.path.split(Platform.pathSeparator).last;
    box = await Hive.openBox<ChatMessageDto>(boxName);
    agendaRepository = FakeAgendaRepository();
    repository = ChatHistoryRepositoryImpl(
      box: box,
      agendaRepository: agendaRepository,
    );
  });

  tearDown(() async {
    if (box.isOpen) {
      await box.deleteFromDisk();
    }
  });

  test(
    'getAll returns an empty list when nothing has been persisted',
    () async {
      expect(await repository.getAll(), isEmpty);
    },
  );

  test('add persists a message retrievable via getAll', () async {
    await repository.add(_message('m1', text: 'What talks are today?'));

    final all = await repository.getAll();

    expect(all, hasLength(1));
    expect(all.single.id, 'm1');
    expect(all.single.text, 'What talks are today?');
  });

  test('getAll returns messages oldest first', () async {
    await repository.add(_message('newest', createdAt: DateTime(2026, 3, 1)));
    await repository.add(_message('oldest', createdAt: DateTime(2026, 1, 1)));
    await repository.add(_message('middle', createdAt: DateTime(2026, 2, 1)));

    final all = await repository.getAll();

    expect(all.map((m) => m.id).toList(), ['oldest', 'middle', 'newest']);
  });

  test(
    're-joins citedTalkIds into full Citations via AgendaRepository',
    () async {
      agendaRepository = FakeAgendaRepository(
        seed: [_talk('talk-001', title: 'On-Device LLMs')],
      );
      repository = ChatHistoryRepositoryImpl(
        box: box,
        agendaRepository: agendaRepository,
      );

      await repository.add(
        _message(
          'm1',
          role: ChatRole.assistant,
          citations: const [
            Citation(talkId: 'talk-001', talkTitle: 'stale title ignored'),
          ],
        ),
      );

      final all = await repository.getAll();

      expect(all.single.citations, hasLength(1));
      expect(all.single.citations.single.talkId, 'talk-001');
      expect(all.single.citations.single.talkTitle, 'On-Device LLMs');
    },
  );

  test('a citation id that no longer resolves is dropped, not surfaced as '
      'an error', () async {
    await repository.add(
      _message(
        'm1',
        role: ChatRole.assistant,
        citations: const [Citation(talkId: 'talk-gone', talkTitle: 'Gone')],
      ),
    );

    final all = await repository.getAll();

    expect(all.single.citations, isEmpty);
  });

  test('add wraps a Hive write failure in ChatPersistenceException', () async {
    await box.close();

    expect(
      () => repository.add(_message('m1')),
      throwsA(isA<ChatPersistenceException>()),
    );
  });

  test('survives being re-opened against the same box (persists across '
      '"restarts")', () async {
    await repository.add(_message('m1', text: 'persisted question'));
    final boxName = box.name;
    await box.close();

    final reopened = await Hive.openBox<ChatMessageDto>(boxName);
    final reopenedRepository = ChatHistoryRepositoryImpl(
      box: reopened,
      agendaRepository: agendaRepository,
    );

    expect((await reopenedRepository.getAll()).single.id, 'm1');
    box = reopened;
  });
}
