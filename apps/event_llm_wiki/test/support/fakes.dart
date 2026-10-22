import 'dart:async';

import 'package:event_llm_wiki/data/services/network_connectivity_service.dart';
import 'package:event_llm_wiki/domain/models/chat_message.dart';
import 'package:event_llm_wiki/domain/models/model_download_status.dart';
import 'package:event_llm_wiki/domain/models/talk.dart';
import 'package:event_llm_wiki/domain/repositories/agenda_repository.dart';
import 'package:event_llm_wiki/domain/repositories/chat_engine_repository.dart';
import 'package:event_llm_wiki/domain/repositories/chat_history_repository.dart';
import 'package:event_llm_wiki/domain/repositories/model_download_repository.dart';

/// In-memory [AgendaRepository] fake backed by a plain `List<Talk>` — no
/// `rootBundle`/asset loading involved. Mirrors `apps/rps_live`'s
/// `test/support/fakes.dart` fakes-over-mocks convention.
class FakeAgendaRepository implements AgendaRepository {
  FakeAgendaRepository({List<Talk>? seed}) : _talks = [...?seed];

  final List<Talk> _talks;

  /// If set, [getAllTalks] throws this instead of succeeding.
  Object? getAllTalksError;

  @override
  Future<List<Talk>> getAllTalks() async {
    final error = getAllTalksError;
    if (error != null) throw error;
    return List.unmodifiable(_talks);
  }

  @override
  Future<Talk> getTalkById(String id) async {
    for (final talk in _talks) {
      if (talk.id == id) return talk;
    }
    throw TalkNotFoundException('No talk with id "$id".');
  }
}

/// In-memory [ChatEngineRepository] fake: no `flutter_litert_lm` engine,
/// no real model, no native inference. Tests drive [emit]/[emitError]/
/// [completeStream] on the currently in-flight [sendMessage] stream to
/// simulate the engine's delta-stream behavior.
class FakeChatEngineRepository implements ChatEngineRepository {
  int initializeCallCount = 0;
  int disposeCallCount = 0;

  /// If set, [initialize] throws this instead of succeeding.
  Object? initializeError;

  StreamController<String>? _activeController;

  /// The most recent prompt passed to [sendMessage], for assertions.
  String? lastPrompt;

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Stream<String> sendMessage(String prompt) {
    lastPrompt = prompt;
    final controller = StreamController<String>();
    _activeController = controller;
    return controller.stream;
  }

  /// Emits a delta chunk on the stream returned by the most recent
  /// [sendMessage] call.
  void emit(String delta) => _activeController?.add(delta);

  void emitError(Object error) => _activeController?.addError(error);

  Future<void> completeStream() async {
    await _activeController?.close();
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}

/// In-memory [ChatHistoryRepository] fake backed by a plain
/// `List<ChatMessage>` — no Hive box, no filesystem involved.
class FakeChatHistoryRepository implements ChatHistoryRepository {
  FakeChatHistoryRepository({List<ChatMessage>? seed}) : _messages = [...?seed];

  final List<ChatMessage> _messages;

  /// If set, [getAll] throws this instead of succeeding.
  Object? getAllError;

  /// If set, [add] throws this instead of succeeding.
  Object? addError;

  @override
  Future<List<ChatMessage>> getAll() async {
    final error = getAllError;
    if (error != null) throw error;
    return List.unmodifiable(_messages);
  }

  @override
  Future<void> add(ChatMessage message) async {
    final error = addError;
    if (error != null) throw error;
    _messages.add(message);
  }
}

/// In-memory [ModelDownloadRepository] fake: no `path_provider`/`http`
/// involved. [checkLocalStatus] returns [localStatus] (defaulting to
/// [ModelDownloadPhase.notDownloaded]); [download] replays whatever events
/// are queued in [downloadEvents] on its returned stream.
class FakeModelDownloadRepository implements ModelDownloadRepository {
  ModelDownloadStatus localStatus = const ModelDownloadStatus(
    phase: ModelDownloadPhase.notDownloaded,
  );

  /// If set, [checkLocalStatus] throws this instead of returning
  /// [localStatus].
  Object? checkLocalStatusError;

  /// Canned Wi-Fi connectivity status returned by [isWifiConnected].
  bool wifiConnected = true;

  /// Events [download] emits, in order, on each call.
  List<ModelDownloadStatus> downloadEvents = const [];

  int downloadCallCount = 0;
  String? lastAuthToken;

  @override
  Future<ModelDownloadStatus> checkLocalStatus() async {
    final error = checkLocalStatusError;
    if (error != null) throw error;
    return localStatus;
  }

  @override
  Future<bool> isWifiConnected() async => wifiConnected;

  @override
  Stream<ModelDownloadStatus> download({String? authToken}) {
    downloadCallCount++;
    lastAuthToken = authToken;
    return Stream.fromIterable(downloadEvents);
  }
}

/// In-memory [NetworkConnectivityService] fake for testing
/// `ModelDownloadRepositoryImpl` without a platform channel.
class FakeNetworkConnectivityService implements NetworkConnectivityService {
  FakeNetworkConnectivityService({this.wifiConnected = true});

  bool wifiConnected;
  int checkCallCount = 0;

  @override
  Future<bool> isWifiConnected() async {
    checkCallCount++;
    return wifiConnected;
  }
}
