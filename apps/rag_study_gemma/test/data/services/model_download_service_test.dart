import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rag_study_gemma/data/services/model_download_service.dart';
import 'package:rag_study_gemma/domain/repositories/model_download_repository.dart';

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  final List<http.BaseRequest> recordedRequests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    recordedRequests.add(request);
    return _handler(request);
  }
}

void main() {
  group('ModelDownloadServiceImpl', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_dl_svc_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'streams chunks to .part file, emits progress, and atomically renames',
      () async {
        final client = _RecordingHttpClient((request) async {
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              [1, 2, 3, 4],
              [5, 6, 7, 8],
            ]),
            200,
            contentLength: 8,
          );
        });

        final service = ModelDownloadServiceImpl(client: client);
        final destPath = '${tempDir.path}/model.litertlm';

        final progressEvents = await service
            .downloadToFile(
              url: Uri.parse(
                'https://huggingface.co/org/repo/resolve/main/m.litertlm',
              ),
              destinationPath: destPath,
            )
            .toList();

        expect(progressEvents, hasLength(2));
        expect(progressEvents[0].bytesReceived, equals(4));
        expect(progressEvents[0].totalBytes, equals(8));
        expect(progressEvents[1].bytesReceived, equals(8));
        expect(progressEvents[1].totalBytes, equals(8));

        final finalFile = File(destPath);
        final partFile = File('$destPath.part');
        expect(await finalFile.exists(), isTrue);
        expect(await partFile.exists(), isFalse);
        expect(await finalFile.readAsBytes(), equals([1, 2, 3, 4, 5, 6, 7, 8]));
      },
    );

    test('sends Authorization header to huggingface.co and strips it on CDN redirect', () async {
      final client = _RecordingHttpClient((request) async {
        if (request.url.host == 'huggingface.co') {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            302,
            headers: {
              'location':
                  'https://us.aws.cdn.hf.co/signed-bucket/model.litertlm',
            },
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.value([10, 20, 30]),
          200,
          contentLength: 3,
        );
      });

      final service = ModelDownloadServiceImpl(client: client);
      final destPath = '${tempDir.path}/redirected.litertlm';

      await service
          .downloadToFile(
            url: Uri.parse(
              'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/m.litertlm',
            ),
            destinationPath: destPath,
            hfToken: 'hf_test_token_123',
          )
          .drain<void>();

      expect(client.recordedRequests, hasLength(2));
      expect(client.recordedRequests[0].followRedirects, isFalse);
      expect(
        client.recordedRequests[0].headers['Authorization'],
        equals('Bearer hf_test_token_123'),
      );
      expect(client.recordedRequests[1].url.host, equals('us.aws.cdn.hf.co'));
      expect(
        client.recordedRequests[1].headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('automatically falls back to fallbackUrl on HTTP 401/403 from primary URL', () async {
      final primaryUri = Uri.parse(
        'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma.litertlm',
      );
      final fallbackUri = Uri.parse(
        'https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/gemma.litertlm',
      );

      final client = _RecordingHttpClient((request) async {
        if (request.url == primaryUri) {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 401);
        }
        if (request.url == fallbackUri) {
          return http.StreamedResponse(
            Stream<List<int>>.value([42, 43, 44]),
            200,
            contentLength: 3,
          );
        }
        return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
      });

      final service = ModelDownloadServiceImpl(client: client);
      final destPath = '${tempDir.path}/fallback.litertlm';

      final events = await service
          .downloadToFile(
            url: primaryUri,
            fallbackUrl: fallbackUri,
            destinationPath: destPath,
            hfToken: 'hf_expired',
          )
          .toList();

      expect(events.last.bytesReceived, equals(3));
      expect(client.recordedRequests, hasLength(2));
      expect(client.recordedRequests[0].url, equals(primaryUri));
      expect(client.recordedRequests[1].url, equals(fallbackUri));
      expect(
        client.recordedRequests[1].headers.containsKey('Authorization'),
        isFalse,
      );
      expect(await File(destPath).readAsBytes(), equals([42, 43, 44]));
    });

    test(
      'automatically falls back to fallbackUrl on HTTP 404 from primary URL',
      () async {
        final primaryUri = Uri.parse(
          'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/missing.litertlm',
        );
        final fallbackUri = Uri.parse(
          'https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/gemma3-1b-it-int4.litertlm',
        );

        final client = _RecordingHttpClient((request) async {
          if (request.url == primaryUri) {
            return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
          }
          return http.StreamedResponse(
            Stream<List<int>>.value([9, 8, 7]),
            200,
            contentLength: 3,
          );
        });

        final service = ModelDownloadServiceImpl(client: client);
        final destPath = '${tempDir.path}/fallback_404.litertlm';

        final events = await service
            .downloadToFile(
              url: primaryUri,
              fallbackUrl: fallbackUri,
              destinationPath: destPath,
            )
            .toList();

        expect(events.last.bytesReceived, equals(3));
        expect(await File(destPath).readAsBytes(), equals([9, 8, 7]));
      },
    );

    test(
      'throws HuggingFaceAuthException when 401/403 and no fallback succeeds',
      () async {
        final client = _RecordingHttpClient((request) async {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 403);
        });

        final service = ModelDownloadServiceImpl(client: client);
        final destPath = '${tempDir.path}/unauthorized.litertlm';

        await expectLater(
          service
              .downloadToFile(
                url: Uri.parse('https://huggingface.co/gated/model.litertlm'),
                destinationPath: destPath,
              )
              .toList(),
          throwsA(isA<HuggingFaceAuthException>()),
        );
        expect(await File(destPath).exists(), isFalse);
        expect(await File('$destPath.part').exists(), isFalse);
      },
    );

    test('cleans up .part file when stream errors mid-download', () async {
      final client = _RecordingHttpClient((request) async {
        final controller = StreamController<List<int>>();
        controller.add([1, 2, 3]);
        controller.addError(const SocketException('Connection reset'));
        unawaited(controller.close());
        return http.StreamedResponse(controller.stream, 200, contentLength: 10);
      });

      final service = ModelDownloadServiceImpl(client: client);
      final destPath = '${tempDir.path}/interrupted.litertlm';

      await expectLater(
        service
            .downloadToFile(
              url: Uri.parse('https://huggingface.co/org/model.litertlm'),
              destinationPath: destPath,
            )
            .toList(),
        throwsA(isA<ModelDownloadException>()),
      );

      expect(await File(destPath).exists(), isFalse);
      expect(await File('$destPath.part').exists(), isFalse);
    });
  });
}
