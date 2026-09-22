import '../../core/error/app_exception.dart';

/// Abstraction over the on-device LLM inference engine.
///
/// This is the single seam the rest of the app depends on for chat
/// inference. It intentionally hides `package:flutter_litert_lm`'s
/// `LiteLmEngine`/`LiteLmConversation` types entirely — no `Notifier`,
/// use case, or widget below `data/repositories/chat_engine_repository_impl.dart`
/// may import `package:flutter_litert_lm` (see `data/services/litert_lm_service.dart`,
/// the one file that is allowed to). This mirrors `rps_live`'s
/// `ClassifierRepository` seam over `package:flutter_litert`.
///
/// Unlike `rps_live`'s `ClassifierRepository` (shared across two screens,
/// hence reference-counted — see its ADR addendum), this app has exactly
/// ONE consumer (`ChatViewModel`, deliberately not `.autoDispose` — see
/// `doc/adr/0003-state-management-riverpod.md`), so the real implementation
/// only needs a simple idempotent-init guard, not reference counting.
abstract class ChatEngineRepository {
  /// Loads the model (from the path validated by
  /// `ValidateDownloadedModelUseCase`/`ModelDownloadRepository`) and
  /// prepares a conversation session. Must be called before [sendMessage].
  ///
  /// Idempotent: calling [initialize] again while already initialized is a
  /// no-op (it does not reload the model or reset conversation history).
  ///
  /// Throws [ModelLoadException] if the model file is missing, corrupt, or
  /// the native engine otherwise fails to load it.
  Future<void> initialize();

  /// Sends [prompt] (the full text built by `BuildChatPromptUseCase`, not
  /// the raw user question) to the loaded model and streams back response
  /// text deltas as they are generated.
  ///
  /// Each emitted `String` is a NEW chunk of text (a delta), not a
  /// cumulative snapshot of the response so far — callers must append, not
  /// overwrite (this matches `flutter_litert_lm`'s own
  /// `LiteLmConversation.sendMessageStream` semantics, confirmed against the
  /// installed package version; see `litert_lm_service.dart`).
  ///
  /// Throws [InferenceException] if generation fails mid-stream (the
  /// implementation should surface this as a stream error, not a thrown
  /// exception before the stream is even returned, since failures here are
  /// typically mid-generation).
  Stream<String> sendMessage(String prompt);

  /// Releases native engine/conversation resources. Safe to call multiple
  /// times.
  Future<void> dispose();
}

/// Thrown by [ChatEngineRepository.initialize] when the on-device model
/// fails to load (missing file, corrupt `.litertlm`, unsupported
/// backend/device combination).
class ModelLoadException extends AppException {
  const ModelLoadException(super.message, {super.cause});
}

/// Surfaced on [ChatEngineRepository.sendMessage]'s stream when generation
/// fails mid-response.
class InferenceException extends AppException {
  const InferenceException(super.message, {super.cause});
}
