import 'package:flutter_litert_lm/flutter_litert_lm.dart';

/// Thin wrapper around `package:flutter_litert_lm`'s `LiteLmEngine` /
/// `LiteLmConversation`.
///
/// **This is the ONLY file in this app allowed to import
/// `package:flutter_litert_lm`** — `ChatEngineRepositoryImpl` depends only
/// on this class, never on `LiteLmEngine`/`LiteLmConversation` directly (see
/// `doc/adr/0003-state-management-riverpod.md`'s compliance rule and
/// `domain/repositories/chat_engine_repository.dart`'s doc comment).
///
/// Deliberately left untested by design (mirrors `apps/rps_live`'s
/// `TfliteClassifierService`/`CameraFrameService` boundary): the native
/// engine, the real ~529 MB model, and real inference are exactly the three
/// things `flutter test` must never touch. Its correctness is instead
/// verified at the two on-device checkpoints in PLAN.md phases 7-8. Keep
/// this class a pure pass-through with no branching logic worth unit
/// testing in isolation — any decision logic (prompt composition, retry
/// policy, etc.) belongs in `domain/use_cases/**` or
/// `ChatEngineRepositoryImpl`, which ARE unit-testable against a
/// `FakeLitertLmService`.
///
/// Confirmed against the installed `flutter_litert_lm: 0.3.0` API surface
/// (`LiteLmEngine.create`, `engine.createConversation`,
/// `conversation.sendMessageStream`): each `LiteLmMessage` emitted by
/// `sendMessageStream` carries a NEW text delta in `.text`, not a
/// cumulative snapshot — [sendMessageStream] below maps that to a plain
/// `Stream<String>` of the same per-chunk deltas, so
/// `ChatEngineRepository.sendMessage`'s callers must append, not overwrite.
abstract class LitertLmService {
  /// Loads the `.litertlm` model at [modelPath] and starts a conversation
  /// session. Must be called before [sendMessageStream].
  Future<void> initialize({required String modelPath});

  /// Sends [prompt] and streams back response text deltas (see the class
  /// doc comment on delta-vs-cumulative semantics).
  Stream<String> sendMessageStream(String prompt);

  /// Releases the native engine/conversation. Safe to call multiple times.
  Future<void> dispose();
}

/// Real implementation backed by `LiteLmEngine`/`LiteLmConversation`.
class LitertLmServiceImpl implements LitertLmService {
  LitertLmServiceImpl({this.backend = LiteLmBackend.cpu});

  /// Hardware backend for inference. Defaults to CPU. GPU/NPU are
  /// Android-only per the installed package's platform support table; see
  /// `doc/adr/0001-llm-runtime-model-selection.md` for why CPU is this
  /// app's default rather than an on-device-detected backend.
  final LiteLmBackend backend;

  LiteLmEngine? _engine;
  LiteLmConversation? _conversation;

  @override
  Future<void> initialize({required String modelPath}) async {
    final engine = await LiteLmEngine.create(
      LiteLmEngineConfig(modelPath: modelPath, backend: backend),
    );
    _engine = engine;
    _conversation = await engine.createConversation();
  }

  @override
  Stream<String> sendMessageStream(String prompt) {
    final conversation = _conversation;
    if (conversation == null) {
      throw StateError(
        'LitertLmServiceImpl.initialize() must complete successfully '
        'before sendMessageStream().',
      );
    }
    // Each emitted LiteLmMessage.text is a DELTA (new tokens only), not a
    // cumulative snapshot — see this class's doc comment. Passed through
    // unmodified here; ChatEngineRepositoryImpl/ChatViewModel are
    // responsible for accumulating deltas into the growing message text.
    return conversation
        .sendMessageStream(prompt)
        .map((message) => message.text);
  }

  @override
  Future<void> dispose() async {
    await _conversation?.dispose();
    _conversation = null;
    await _engine?.dispose();
    _engine = null;
  }
}
