import 'dart:async';

import 'package:http/http.dart' as http;

/// One chunk of a streamed model download: a batch of bytes plus the
/// response's total content length, when known.
class ModelDownloadChunk {
  const ModelDownloadChunk({required this.bytes, required this.totalBytes});

  final List<int> bytes;

  /// From the response's `Content-Length` header, or null if the server did
  /// not provide one (progress should then be rendered as indeterminate —
  /// see `ModelDownloadStatus.progress`).
  final int? totalBytes;
}

/// Thin wrapper around a streamed `package:http` GET request for the model
/// file.
///
/// Abstracted so tests can substitute a `FakeModelDownloadService` emitting
/// canned [ModelDownloadChunk]s (including a simulated mid-stream failure)
/// from a `StreamController`, with no real network call involved.
abstract class ModelDownloadService {
  /// Streams the response body for a GET request to [modelUrl] in chunks.
  ///
  /// Throws (as a stream error) on a non-2xx response or a network failure
  /// — `ModelDownloadRepositoryImpl` is responsible for wrapping that into
  /// `ModelDownloadException`/a `ModelDownloadPhase.failed` status event.
  Stream<ModelDownloadChunk> download(Uri modelUrl);
}

/// Real implementation backed by `package:http`'s streamed request API
/// (`http.Client.send` with a `http.Request`, not `http.get`, so bytes are
/// delivered incrementally instead of buffering the full ~529 MB in memory
/// before this stream emits anything).
class ModelDownloadServiceImpl implements ModelDownloadService {
  ModelDownloadServiceImpl({http.Client? client, String? authToken})
    : _client = client ?? http.Client(),
      // `litert-community/Gemma3-1B-IT` is gated behind the Gemma license —
      // an unauthenticated GET returns HTTP 401 (discovered during the
      // on-device checkpoint A attempt; see doc/adr/0001's follow-up note
      // and main.dart). Sourced from `--dart-define=HF_TOKEN=...` (or
      // `--dart-define-from-file`) by default so no token is ever
      // hardcoded/committed; passing `authToken` explicitly is for tests.
      _authToken = authToken ?? const String.fromEnvironment('HF_TOKEN');

  final http.Client _client;
  final String _authToken;

  @override
  Stream<ModelDownloadChunk> download(Uri modelUrl) {
    final controller = StreamController<ModelDownloadChunk>();

    Future<void> run() async {
      try {
        final request = http.Request('GET', modelUrl);
        if (_authToken.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $_authToken';
        }
        final response = await _client.send(request);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
            'GET $modelUrl returned HTTP ${response.statusCode}.',
            modelUrl,
          );
        }
        final totalBytes = response.contentLength;
        await for (final bytes in response.stream) {
          controller.add(
            ModelDownloadChunk(bytes: bytes, totalBytes: totalBytes),
          );
        }
        await controller.close();
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }
}
