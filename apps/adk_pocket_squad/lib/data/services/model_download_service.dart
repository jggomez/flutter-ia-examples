import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/model_download_state.dart';

/// Incremental byte progress emitted while streaming a model artifact to disk.
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
  });

  final int bytesReceived;
  final int totalBytes;

  double get progress =>
      totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// Exception thrown when model download or validation fails.
class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => message;
}

/// Service that resolves the on-device `gemma-4-E2B-it.litertlm` (2.58 GB)
/// path and performs atomic `.part` downloads with cross-host redirect
/// sanitization (`Authorization` stripped when leaving `huggingface.co`).
class ModelDownloadService {
  ModelDownloadService({
    http.Client? client,
    Future<Directory> Function()? documentsDirectoryProvider,
    Future<Directory> Function()? supportDirectoryProvider,
    String? defaultHfToken,
    this.minValidBytesOverride,
  }) : _client = client ?? http.Client(),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _defaultHfToken =
           defaultHfToken ?? const String.fromEnvironment('HF_TOKEN');

  static const String modelFileName = 'gemma-4-E2B-it.litertlm';
  static const String primaryModelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';
  static const int minValidModelBytes = 400 * 1024 * 1024; // 400 MB

  static const int maxRedirects = 8;
  static const Set<int> _redirectStatusCodes = <int>{301, 302, 303, 307, 308};

  final http.Client _client;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<Directory> Function() _supportDirectoryProvider;
  final String _defaultHfToken;
  final int? minValidBytesOverride;

  int get effectiveMinValidBytes => minValidBytesOverride ?? minValidModelBytes;

  /// Checks candidate locations in order:
  /// 1. `<getApplicationDocumentsDirectory()>/gemma-4-E2B-it.litertlm`
  /// 2. `<getApplicationSupportDirectory()>/models/gemma-4-E2B-it.litertlm`
  /// 3. `<getApplicationSupportDirectory()>/gemma-4-E2B-it.litertlm`
  ///
  /// If any candidate exists and has length `>= minBytes`, returns that path.
  /// Otherwise returns the primary target path inside `<documentsDir>/gemma-4-E2B-it.litertlm`.
  Future<String> resolveModelFilePath({int? minBytes}) async {
    final threshold = minBytes ?? effectiveMinValidBytes;
    final candidates = await _candidatePaths();
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        final length = await file.length();
        if (length >= threshold) {
          return candidate;
        }
      }
    }
    return candidates.first;
  }

  /// Alias for [resolveModelFilePath].
  Future<String> getModelFilePath({int? minBytes}) =>
      resolveModelFilePath(minBytes: minBytes);

  /// Returns the existing valid model file path if present and `>= minBytes`,
  /// or `null` if not yet downloaded.
  Future<String?> findExistingModelPath({int? minBytes}) async {
    final threshold = minBytes ?? effectiveMinValidBytes;
    final candidates = await _candidatePaths();
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        final length = await file.length();
        if (length >= threshold) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Returns `true` when `gemma-4-E2B-it.litertlm` exists on disk and meets
  /// the minimum valid byte threshold (`>= 400 MB` by default).
  Future<bool> isModelDownloaded({int? minBytes}) async {
    final existing = await findExistingModelPath(minBytes: minBytes);
    return existing != null;
  }

  /// Streams [ModelDownloadState] updates while downloading the `.litertlm`
  /// artifact into `<targetPath>.part` and atomically renaming upon validation.
  Stream<ModelDownloadState> downloadModel({
    String? hfToken,
    String? url,
    int? minBytes,
  }) async* {
    final existing = await findExistingModelPath(minBytes: minBytes);
    if (existing != null) {
      final length = await File(existing).length();
      yield ModelDownloadState(
        phase: ModelDownloadPhase.ready,
        downloadedBytes: length,
        totalBytes: length,
        progress: 1.0,
        isOnWifi: true,
        modelFilePath: existing,
      );
      return;
    }

    final destinationPath = await resolveModelFilePath(minBytes: minBytes);
    final targetUri = Uri.parse(
      (url != null && url.trim().isNotEmpty) ? url.trim() : primaryModelUrl,
    );

    yield const ModelDownloadState(
      phase: ModelDownloadPhase.downloading,
      downloadedBytes: 0,
      totalBytes: 0,
      progress: 0.0,
      isOnWifi: true,
    );

    await for (final progress in downloadToFile(
      url: targetUri,
      destinationPath: destinationPath,
      hfToken: hfToken,
      minBytes: minBytes,
    )) {
      yield ModelDownloadState(
        phase: ModelDownloadPhase.downloading,
        downloadedBytes: progress.bytesReceived,
        totalBytes: progress.totalBytes,
        progress: progress.progress,
        isOnWifi: true,
        modelFilePath: destinationPath,
      );
    }

    final finalFile = File(destinationPath);
    final finalBytes = await finalFile.exists() ? await finalFile.length() : 0;
    yield ModelDownloadState(
      phase: ModelDownloadPhase.ready,
      downloadedBytes: finalBytes,
      totalBytes: finalBytes,
      progress: 1.0,
      isOnWifi: true,
      modelFilePath: destinationPath,
    );
  }

  /// Streams incremental [ModelDownloadProgress] events while writing to
  /// `<destinationPath>.part` and atomically renaming to [destinationPath].
  Stream<ModelDownloadProgress> downloadToFile({
    Uri? url,
    required String destinationPath,
    Uri? fallbackUrl,
    String? hfToken,
    int? minBytes,
  }) {
    final controller = StreamController<ModelDownloadProgress>();
    final effectiveUri = url ?? Uri.parse(primaryModelUrl);
    final threshold = minBytes ?? effectiveMinValidBytes;

    Future<void> run() async {
      final partFile = File('$destinationPath.part');
      IOSink? sink;
      var activeUrl = effectiveUri;

      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }
        await partFile.parent.create(recursive: true);

        final trimmedToken = hfToken?.trim() ?? '';
        final effectiveToken = trimmedToken.isNotEmpty
            ? trimmedToken
            : _defaultHfToken.trim();

        var response = await _sendFollowingRedirects(
          effectiveUri,
          bearerToken: effectiveToken,
        );

        if ((response.statusCode == 401 ||
                response.statusCode == 403 ||
                response.statusCode == 404) &&
            fallbackUrl != null &&
            fallbackUrl != effectiveUri) {
          await response.stream.drain<void>();
          activeUrl = fallbackUrl;
          response = await _sendFollowingRedirects(
            fallbackUrl,
            bearerToken: null,
          );
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          await response.stream.drain<void>();
          throw ModelDownloadException(
            'Hugging Face access denied (HTTP ${response.statusCode}) for $activeUrl. '
            'Provide a valid Hugging Face token or accept the repository license.',
            statusCode: response.statusCode,
          );
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.drain<void>();
          throw ModelDownloadException(
            'Model download failed with HTTP ${response.statusCode} for $activeUrl.',
            statusCode: response.statusCode,
          );
        }

        final totalBytes = response.contentLength ?? 0;
        var bytesReceived = 0;
        sink = partFile.openWrite(mode: FileMode.writeOnly);

        await for (final chunk in response.stream) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          controller.add(
            ModelDownloadProgress(
              bytesReceived: bytesReceived,
              totalBytes: totalBytes,
            ),
          );
        }

        await sink.flush();
        await sink.close();
        sink = null;

        final finalPartSize = await partFile.length();
        if (finalPartSize < threshold) {
          await partFile.delete();
          throw ModelDownloadException(
            'Downloaded model file ($finalPartSize bytes) is smaller than minimum valid size ($threshold bytes).',
          );
        }

        await partFile.rename(destinationPath);
        await controller.close();
      } catch (error, stackTrace) {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
          sink = null;
        }
        try {
          if (await partFile.exists()) {
            await partFile.delete();
          }
        } catch (_) {}

        final mappedError = error is ModelDownloadException
            ? error
            : ModelDownloadException(
                'Failed while downloading model from $activeUrl: $error',
                cause: error,
              );
        controller.addError(mappedError, stackTrace);
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// Resolves up to [maxRedirects] hops manually with `followRedirects = false`
  /// so `Authorization: Bearer` is only sent to `huggingface.co` and stripped
  /// when redirected to cross-host CDN domains (`cdn-lfs.huggingface.co`, `*.hf.co`).
  Future<http.StreamedResponse> _sendFollowingRedirects(
    Uri initialUrl, {
    required String? bearerToken,
  }) async {
    var currentUri = initialUrl;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request('GET', currentUri)..followRedirects = false;
      if (bearerToken != null &&
          bearerToken.isNotEmpty &&
          _isSameOriginHost(initialUrl.host, currentUri.host)) {
        request.headers['Authorization'] = 'Bearer $bearerToken';
      }
      final response = await _client.send(request);
      if (!_redirectStatusCodes.contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty || hop == maxRedirects) {
        return response;
      }
      await response.stream.drain<void>();
      currentUri = currentUri.resolve(location);
    }
    throw ModelDownloadException(
      'Too many redirects while downloading $initialUrl.',
    );
  }

  static bool _isSameOriginHost(String initialHost, String targetHost) {
    return initialHost.toLowerCase() == targetHost.toLowerCase();
  }

  Future<List<String>> _candidatePaths() async {
    final paths = <String>[];
    try {
      final docsDir = await _documentsDirectoryProvider();
      paths.add('${docsDir.path}/$modelFileName');
    } catch (_) {}

    try {
      final supportDir = await _supportDirectoryProvider();
      paths.add('${supportDir.path}/models/$modelFileName');
      paths.add('${supportDir.path}/$modelFileName');
    } catch (_) {}

    if (paths.isEmpty) {
      paths.add('${Directory.systemTemp.path}/$modelFileName');
    }
    return paths;
  }
}

/// Concrete subclass alias for DI containers expecting `*Impl` naming.
class ModelDownloadServiceImpl extends ModelDownloadService {
  ModelDownloadServiceImpl({
    super.client,
    super.documentsDirectoryProvider,
    super.supportDirectoryProvider,
    super.defaultHfToken,
    super.minValidBytesOverride,
  });
}
