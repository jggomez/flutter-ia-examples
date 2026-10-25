import '../../core/error/app_exception.dart';

/// Thrown when loading the on-device generative or embedding model fails.
class ModelLoadException extends AppException {
  const ModelLoadException(super.message, {super.cause});
}

/// Thrown when streaming or generating a chat response fails.
class InferenceException extends AppException {
  const InferenceException(super.message, {super.cause});
}

/// Contract for the on-device Gemma 3 1B IT conversational inference engine.
abstract interface class ChatEngineRepository {
  Future<void> initialize();

  Stream<String> sendMessage(String prompt);

  Future<void> resetConversation();

  Future<void> dispose();
}
