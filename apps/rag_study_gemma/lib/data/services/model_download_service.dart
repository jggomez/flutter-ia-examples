import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/error/app_exception.dart';
import '../../domain/repositories/model_download_repository.dart';

/// Incremental byte progress emitted while streaming a model file to disk.
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
  });

  final int bytesReceived;
  final int totalBytes;
}

/// Service contract for streaming a remote model artifact to a local file path.
abstract interface class ModelDownloadService {
  Stream<ModelDownloadProgress> downloadToFile({
    required Uri url,
    required String destinationPath,
    Uri? fallbackUrl,
    String? hfToken,
  });
}

/// Real implementation backed by `package:http` streamed GET requests with
/// manual cross-host redirect handling, automatic ungated mirror fallback,
/// buffered `IOSink` to `<destinationPath>.part`, and atomic rename.
class ModelDownloadServiceImpl implements ModelDownloadService {
  ModelDownloadServiceImpl({http.Client? client, String? defaultHfToken})
    : _client = client ?? http.Client(),
      _defaultHfToken =
          defaultHfToken ?? const String.fromEnvironment('HF_TOKEN');

  static const int _maxRedirects = 6;
  static const Set<int> _redirectStatusCodes = {301, 302, 303, 307, 308};

  final http.Client _client;
  final String _defaultHfToken;

  @override
  Stream<ModelDownloadProgress> downloadToFile({
    required Uri url,
    required String destinationPath,
    Uri? fallbackUrl,
    String? hfToken,
  }) {
    final controller = StreamController<ModelDownloadProgress>();

    Future<void> run() async {
      final partFile = File('$destinationPath.part');
      IOSink? sink;
      var activeUrl = url;
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
          url,
          bearerToken: effectiveToken,
        );

        if ((response.statusCode == 401 ||
                response.statusCode == 403 ||
                response.statusCode == 404) &&
            fallbackUrl != null &&
            fallbackUrl != url) {
          await response.stream.drain<void>();
          activeUrl = fallbackUrl;
          response = await _sendFollowingRedirects(
            fallbackUrl,
            bearerToken: null,
          );
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          await response.stream.drain<void>();
          throw HuggingFaceAuthException(
            'HuggingFace rejected access (HTTP ${response.statusCode}) for $activeUrl. '
            'Provide a valid HuggingFace token or accept the repository license.',
          );
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.drain<void>();
          throw ModelDownloadException(
            'Download failed with HTTP ${response.statusCode} for $activeUrl.',
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

        final mappedError = error is AppException
            ? error
            : ModelDownloadException(
                'Failed while downloading model from $activeUrl.',
                cause: error,
              );
        controller.addError(mappedError, stackTrace);
        await controller.close();
      }
    }

    unawaited(run());
    return controller.stream;
  }

  /// Resolves up to [_maxRedirects] hops manually so `Authorization: Bearer`
  /// is sent only to [initialUrl]'s host (`huggingface.co`) and stripped when
  /// redirected to pre-signed CDN hosts (e.g. `us.aws.cdn.hf.co`).
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
    throw ModelDownloadException(
      'Too many redirects while downloading $initialUrl.',
    );
  }
}
