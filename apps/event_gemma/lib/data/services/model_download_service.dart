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
  Stream<ModelDownloadChunk> download(Uri modelUrl, {String? authToken});
}

/// Real implementation backed by `package:http`'s streamed request API
/// (`http.Client.send` with a `http.Request`, not `http.get`, so bytes are
/// delivered incrementally instead of buffering the full ~529 MB in memory
/// before this stream emits anything).
class ModelDownloadServiceImpl implements ModelDownloadService {
  ModelDownloadServiceImpl({
    http.Client? client,
    String? authToken,
    Uri? fallbackModelUrl,
  }) : _client = client ?? http.Client(),
       // `litert-community/Gemma3-1B-IT` is gated behind the Gemma license —
       // an unauthenticated GET returns HTTP 401 (discovered during the
       // on-device checkpoint A attempt; see doc/adr/0001's follow-up note
       // and main.dart). Sourced from `--dart-define=HF_TOKEN=...` (or
       // `--dart-define-from-file`) by default so no token is ever
       // hardcoded/committed; passing `authToken` explicitly is for tests.
       _authToken = authToken ?? const String.fromEnvironment('HF_TOKEN'),
       _fallbackModelUrl = fallbackModelUrl ?? defaultFallbackModelUrl;

  /// Public, ungated HuggingFace mirror of `Gemma 3 1B-IT int4` `.litertlm`
  /// used automatically when the primary gated repository returns `401`/`403`
  /// (e.g., no `HF_TOKEN` provided or the user's account has not yet clicked
  /// "Agree" on the gated repository license web page).
  static final Uri defaultFallbackModelUrl = Uri.parse(
    'https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/'
    'gemma3-1b-it-int4.litertlm',
  );

  static const int _maxRedirects = 6;
  static const Set<int> _redirectStatusCodes = {301, 302, 303, 307, 308};

  final http.Client _client;
  final String _authToken;
  final Uri? _fallbackModelUrl;

  @override
  Stream<ModelDownloadChunk> download(Uri modelUrl, {String? authToken}) {
    final controller = StreamController<ModelDownloadChunk>();

    Future<void> run() async {
      try {
        final trimmedOverride = authToken?.trim() ?? '';
        final effectiveToken = trimmedOverride.isNotEmpty
            ? trimmedOverride
            : _authToken.trim();

        var response = await _sendFollowingRedirects(
          modelUrl,
          bearerToken: effectiveToken,
        );

        final fallbackUrl = _fallbackModelUrl;
        if ((response.statusCode == 401 || response.statusCode == 403) &&
            fallbackUrl != null &&
            fallbackUrl != modelUrl) {
          await response.stream.drain<void>();
          response = await _sendFollowingRedirects(
            fallbackUrl,
            bearerToken: null,
          );
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.drain<void>();
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

  /// Sends a `GET` request with `followRedirects = false` and resolves up to
  /// [_maxRedirects] hops manually so `Authorization: Bearer <token>` is only
  /// sent to [initialUrl]'s host (`huggingface.co`) and stripped when
  /// redirected to pre-signed CDN hosts (`us.aws.cdn.hf.co`).
  Future<http.StreamedResponse> _sendFollowingRedirects(
    Uri initialUrl, {
    required String? bearerToken,
  }) async {
    var currentUri = initialUrl;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('GET', currentUri)..followRedirects = false;
      if (bearerToken != null &&
          bearerToken.isNotEmpty &&
          currentUri.host == initialUrl.host) {
        request.headers['Authorization'] = 'Bearer $bearerToken';
      }
      final response = await _client.send(request);
      if (!_redirectStatusCodes.contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty || hop == _maxRedirects) {
        return response;
      }
      await response.stream.drain<void>();
      currentUri = currentUri.resolve(location);
    }
    throw http.ClientException(
      'Too many redirects while downloading $initialUrl.',
      initialUrl,
    );
  }
}
