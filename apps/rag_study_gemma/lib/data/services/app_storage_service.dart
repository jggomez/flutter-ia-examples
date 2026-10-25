import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Thin wrapper around `package:path_provider` that resolves the on-disk paths
/// for the downloaded `.litertlm` models and the `sqlite-vec` vector database.
abstract interface class AppStorageService {
  /// Final path of the EmbeddingGemma 2 `.litertlm` artifact.
  Future<String> get embeddingModelFilePath;

  /// Final path of the Gemma 4 E2B IT `.litertlm` artifact.
  Future<String> get llmModelFilePath;

  /// On-disk path of the `sqlite-vec` (`vec0`) RAG database file.
  Future<String> get ragSqliteDbPath;
}

/// Real implementation backed by `getApplicationSupportDirectory()`.
class AppStorageServiceImpl implements AppStorageService {
  AppStorageServiceImpl({
    Future<Directory> Function()? supportDirectoryProvider,
    this.embeddingModelFileName = 'embeddinggemma-2-text-270m.litertlm',
    this.llmModelFileName = 'gemma-4-E2B-it.litertlm',
    this.ragSqliteDbFileName = 'study_gemma_rag.sqlite',
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;
  final String embeddingModelFileName;
  final String llmModelFileName;
  final String ragSqliteDbFileName;

  String? _cachedSupportDirPath;

  Future<String> get _supportDirPath async {
    final cached = _cachedSupportDirPath;
    if (cached != null) return cached;
    final dir = await _supportDirectoryProvider();
    _cachedSupportDirPath = dir.path;
    return dir.path;
  }

  @override
  Future<String> get embeddingModelFilePath async =>
      '${await _supportDirPath}/$embeddingModelFileName';

  @override
  Future<String> get llmModelFilePath async =>
      '${await _supportDirPath}/$llmModelFileName';

  @override
  Future<String> get ragSqliteDbPath async =>
      '${await _supportDirPath}/$ragSqliteDbFileName';
}
