// ignore_for_file: prefer_initializing_formals

import '../../core/error/app_exception.dart';
import '../../domain/repositories/chat_engine_repository.dart';
import '../services/app_storage_service.dart';
import '../services/edge_ai_rag_service.dart';

/// Implementation of [ChatEngineRepository] backed by [EdgeAiRagService] and
/// [AppStorageService].
class ChatEngineRepositoryImpl implements ChatEngineRepository {
  ChatEngineRepositoryImpl({
    required EdgeAiRagService edgeAiRagService,
    AppStorageService? appStorageService,
  }) : _edgeAiRagService = edgeAiRagService,
       _appStorageService = appStorageService ?? AppStorageServiceImpl();

  final EdgeAiRagService _edgeAiRagService;
  final AppStorageService _appStorageService;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final llmPath = await _appStorageService.llmModelFilePath;
      await _edgeAiRagService.initializeLlm(llmModelPath: llmPath);
      _initialized = true;
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        ModelLoadException(
          'Failed to initialize on-device Gemma 4 E2B IT model.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<String> sendMessage(String prompt) {
    return _edgeAiRagService.sendMessageStream(prompt).handleError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (error is AppException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        InferenceException(
          'On-device Gemma 4 E2B IT response generation failed.',
          cause: error,
        ),
        stackTrace,
      );
    });
  }

  @override
  Future<void> resetConversation() async {
    try {
      await _edgeAiRagService.resetConversation();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        InferenceException(
          'Failed to reset on-device conversation session.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _edgeAiRagService.disposeLlm();
    } finally {
      _initialized = false;
    }
  }
}
