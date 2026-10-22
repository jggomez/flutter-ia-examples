import 'dart:async';

import 'package:event_gemma/data/services/model_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ModelDownloadServiceImpl', () {
    test('streams response body chunks with the Content-Length as '
        'totalBytes', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        expect(request.method, 'GET');
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5],
          ]),
          200,
          contentLength: 5,
        );
      });
      final service = ModelDownloadServiceImpl(client: client);

      final chunks = await service
          .download(Uri.parse('https://example.com/model.litertlm'))
          .toList();

      expect(chunks, hasLength(2));
      expect(chunks[0].bytes, [1, 2, 3]);
      expect(chunks[0].totalBytes, 5);
      expect(chunks[1].bytes, [4, 5]);
    });

    test('totalBytes is null when the server omits Content-Length', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2, 3],
          ]),
          200,
        );
      });
      final service = ModelDownloadServiceImpl(client: client);

      final chunks = await service
          .download(Uri.parse('https://example.com/model.litertlm'))
          .toList();

      expect(chunks.single.totalBytes, isNull);
    });

    test('a non-2xx response surfaces as a stream error', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(const Stream.empty(), 404);
      });
      final service = ModelDownloadServiceImpl(client: client);

      expect(
        service.download(Uri.parse('https://example.com/missing')).toList(),
        throwsA(anything),
      );
    });

    test('a network failure surfaces as a stream error', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        throw const SocketExceptionStub();
      });
      final service = ModelDownloadServiceImpl(client: client);

      expect(
        service.download(Uri.parse('https://example.com/model')).toList(),
        throwsA(anything),
      );
    });

    test('sends a Bearer Authorization header when authToken is set', () async {
      String? capturedAuthHeader;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final service = ModelDownloadServiceImpl(
        client: client,
        authToken: 'hf_test_token',
      );

      await service.download(Uri.parse('https://example.com/model')).toList();

      expect(capturedAuthHeader, 'Bearer hf_test_token');
    });

    test('sends no Authorization header when authToken is empty', () async {
      String? capturedAuthHeader = 'unset';
      final client = MockClient.streaming((request, bodyStream) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final service = ModelDownloadServiceImpl(client: client, authToken: '');

      await service.download(Uri.parse('https://example.com/model')).toList();

      expect(capturedAuthHeader, isNull);
    });

    test('per-call authToken overrides constructor authToken', () async {
      String? capturedAuthHeader;
      final client = MockClient.streaming((request, bodyStream) async {
        capturedAuthHeader = request.headers['Authorization'];
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final service = ModelDownloadServiceImpl(client: client, authToken: '');

      await service
          .download(
            Uri.parse('https://example.com/model'),
            authToken: 'hf_runtime_token',
          )
          .toList();

      expect(capturedAuthHeader, 'Bearer hf_runtime_token');
    });

    test('follows 302 cross-host redirects and strips Authorization header on '
        'redirected CDN host', () async {
      final capturedRequests = <http.BaseRequest>[];
      final client = MockClient.streaming((request, bodyStream) async {
        capturedRequests.add(request);
        if (request.url.host == 'huggingface.co') {
          return http.StreamedResponse(
            const Stream.empty(),
            302,
            headers: {
              'location': 'https://us.aws.cdn.hf.co/signed-bucket/model.bin',
            },
          );
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            [10, 20, 30],
          ]),
          200,
          contentLength: 3,
        );
      });

      final service = ModelDownloadServiceImpl(
        client: client,
        authToken: 'hf_secret_token',
      );

      final chunks = await service
          .download(
            Uri.parse(
              'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.litertlm',
            ),
          )
          .toList();

      expect(capturedRequests, hasLength(2));
      expect(
        capturedRequests[0].headers['Authorization'],
        'Bearer hf_secret_token',
      );
      expect(capturedRequests[1].url.host, 'us.aws.cdn.hf.co');
      expect(capturedRequests[1].headers['Authorization'], isNull);
      expect(chunks, hasLength(1));
      expect(chunks.single.bytes, [10, 20, 30]);
    });

    test('falls back to public ungated mirror without Authorization when '
        'primary gated URL returns 401 or 403', () async {
      final capturedRequests = <http.BaseRequest>[];
      final fallbackUrl = Uri.parse(
        'https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/gemma3-1b-it-int4.litertlm',
      );
      final client = MockClient.streaming((request, bodyStream) async {
        capturedRequests.add(request);
        if (request.url.path.contains('litert-community')) {
          return http.StreamedResponse(const Stream.empty(), 403);
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            [7, 8, 9],
          ]),
          200,
          contentLength: 3,
        );
      });

      final service = ModelDownloadServiceImpl(
        client: client,
        authToken: 'hf_unaccepted_license_token',
        fallbackModelUrl: fallbackUrl,
      );

      final chunks = await service
          .download(
            Uri.parse(
              'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/model.litertlm',
            ),
          )
          .toList();

      expect(capturedRequests, hasLength(2));
      expect(
        capturedRequests[0].headers['Authorization'],
        'Bearer hf_unaccepted_license_token',
      );
      expect(capturedRequests[1].url, fallbackUrl);
      expect(capturedRequests[1].headers['Authorization'], isNull);
      expect(chunks.single.bytes, [7, 8, 9]);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
