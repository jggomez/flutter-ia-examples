import 'dart:async';

import 'package:event_llm_wiki/data/services/model_download_service.dart';
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
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
