import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

/// Thin wrapper around `package:flutter_edge_ai` and
/// `package:flutter_edge_ai_litertlm`.
///
/// **This is the ONLY file in this app allowed to import
/// `package:flutter_edge_ai` or `package:flutter_edge_ai_litertlm`** —
/// `ChatEngineRepositoryImpl` depends only on this class, never on the
/// inference runtime directly (see `doc/adr/0006-flutter-edge-ai-litertlm-migration-and-ui-revamp.md`).
///
/// Deliberately left untested by design (mirrors `apps/rps_live`'s
/// `TfliteClassifierService`/`CameraFrameService` boundary): the native
/// engine, the real ~529 MB model, and real inference are exactly the three
/// things `flutter test` must never touch. Its correctness is instead
/// verified at the on-device checkpoints. Keep this class a pure pass-through
/// with no branching logic worth unit testing in isolation — any decision logic
/// belongs in `domain/use_cases/**` or `ChatEngineRepositoryImpl`, which ARE
/// unit-testable against a fake.
///
/// Each `TextResponse` emitted by `chat.generateChatResponseAsync()` carries
/// a NEW text delta in `.token`, not a cumulative snapshot — [sendMessageStream]
/// yields each `response.token` so `ChatEngineRepository.sendMessage` callers
/// append, not overwrite.
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

/// Real implementation backed by `flutter_edge_ai` and `LiteRtLmEngine`.
class LitertLmServiceImpl implements LitertLmService {
  LitertLmServiceImpl({this.backendFallback = true});

  /// Whether LiteRT-LM falls back from accelerator to CPU if backend fails.
  final bool backendFallback;

  InferenceModel? _model;
  InferenceChat? _chat;

  @override
  Future<void> initialize({required String modelPath}) async {
    await FlutterEdgeAi.initialize(
      inferenceEngines: [LiteRtLmEngine(backendFallback: backendFallback)],
    );
    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();
    final model = await FlutterEdgeAi.getActiveModel();
    _model = model;
    _chat = await model.createChat(
      systemInstruction:
          'You are Event Gemma, the on-device assistant for the On-Device AI Conference 2026. '
          'Always reply in the same language as the user. Ground your answers in the conference talks.',
    );
  }

  @override
  Stream<String> sendMessageStream(String prompt) async* {
    final chat = _chat;
    if (chat == null) {
      throw StateError(
        'LitertLmServiceImpl.initialize() must complete successfully before sendMessageStream().',
      );
    }
    await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
  }
}
