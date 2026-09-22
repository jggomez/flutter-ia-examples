// See `agenda_repository_impl.dart`'s matching comment: named-parameter
// fields are assigned manually (not via initializing formals) so
// `main.dart` can still pass them by name.
// ignore_for_file: prefer_initializing_formals

import '../../domain/repositories/chat_engine_repository.dart';
import '../services/litert_lm_service.dart';

/// [ChatEngineRepository] backed by [LitertLmService].
///
/// ## Lifecycle: idempotent init guard, not reference counting
///
/// `apps/rps_live`'s `ClassifierRepositoryImpl` needed full reference
/// counting (`_activeSessions`) because its `ClassifierRepository` was
/// shared across TWO screens (`vs_ai` and `practice`), both `.autoDispose`,
/// racing `initialize()`/`dispose()` calls against each other on tab switch
/// (see the addendum to `apps/rps_live/doc/adr/0001-state-management-riverpod.md`).
///
/// This app has exactly ONE consumer of [ChatEngineRepository]:
/// `ChatViewModel`, which is deliberately NOT `.autoDispose` (see
/// `doc/adr/0003-state-management-riverpod.md`) — the 529 MB model loads
/// once and stays loaded for the app session, with no second screen ever
/// calling [initialize]/[dispose] concurrently. There is no
/// tab-switch-driven init/dispose race to guard against, so a plain
/// idempotent boolean guard is sufficient and correct here: [initialize]
/// while already initialized is a no-op; [dispose] is safe to call multiple
/// times. Do not "upgrade" this to reference counting without a new
/// consumer actually appearing — see PLAN.md phase 9's regression test,
/// which pins exactly this (the fake engine's `create()` is asserted to run
/// at most once across a tab-away/tab-back cycle).
class ChatEngineRepositoryImpl implements ChatEngineRepository {
  ChatEngineRepositoryImpl({
    required LitertLmService litertLmService,
    required String modelPath,
  }) : _litertLmService = litertLmService,
       _modelPath = modelPath;

  final LitertLmService _litertLmService;
  final String _modelPath;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _litertLmService.initialize(modelPath: _modelPath);
      _initialized = true;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelLoadException(
          'Failed to load the on-device model at $_modelPath.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<String> sendMessage(String prompt) {
    return _litertLmService.sendMessageStream(prompt).handleError((
      Object error,
      StackTrace stackTrace,
    ) {
      Error.throwWithStackTrace(
        InferenceException('Generation failed mid-response.', cause: error),
        stackTrace,
      );
    });
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    await _litertLmService.dispose();
    _initialized = false;
  }
}
