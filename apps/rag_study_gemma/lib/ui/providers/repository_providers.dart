import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/chat_engine_repository.dart';
import '../../domain/repositories/chat_history_repository.dart';
import '../../domain/repositories/document_ingestion_repository.dart';
import '../../domain/repositories/model_download_repository.dart';
import '../../domain/repositories/rag_index_repository.dart';

/// Single DI composition root for StudyGemma repositories.
///
/// All providers throw [UnimplementedError] until overridden in `main.dart`
/// or inside test `ProviderScope` / `ProviderContainer` configurations.
final documentIngestionRepositoryProvider =
    Provider<DocumentIngestionRepository>((ref) {
      throw UnimplementedError(
        'documentIngestionRepositoryProvider must be overridden in ProviderScope.',
      );
    });

final ragIndexRepositoryProvider = Provider<RagIndexRepository>((ref) {
  throw UnimplementedError(
    'ragIndexRepositoryProvider must be overridden in ProviderScope.',
  );
});

final chatEngineRepositoryProvider = Provider<ChatEngineRepository>((ref) {
  throw UnimplementedError(
    'chatEngineRepositoryProvider must be overridden in ProviderScope.',
  );
});

final chatHistoryRepositoryProvider = Provider<ChatHistoryRepository>((ref) {
  throw UnimplementedError(
    'chatHistoryRepositoryProvider must be overridden in ProviderScope.',
  );
});

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((
  ref,
) {
  throw UnimplementedError(
    'modelDownloadRepositoryProvider must be overridden in ProviderScope.',
  );
});
