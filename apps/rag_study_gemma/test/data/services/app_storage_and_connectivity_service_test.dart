import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rag_study_gemma/data/services/app_storage_service.dart';
import 'package:rag_study_gemma/data/services/network_connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppStorageServiceImpl', () {
    test('resolves expected model and sqlite database file paths under support dir', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'app_storage_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final service = AppStorageServiceImpl(
        supportDirectoryProvider: () async => tempDir,
      );

      expect(
        await service.embeddingModelFilePath,
        equals('${tempDir.path}/embeddinggemma-2-text-270m.litertlm'),
      );
      expect(
        await service.llmModelFilePath,
        equals('${tempDir.path}/gemma-4-E2B-it.litertlm'),
      );
      expect(
        await service.ragSqliteDbPath,
        equals('${tempDir.path}/study_gemma_rag.sqlite'),
      );
    });
  });

  group('NetworkConnectivityServiceImpl', () {
    const channel = MethodChannel(
      'com.jggomez.flutterai.rag_study_gemma/network',
    );
    const service = NetworkConnectivityServiceImpl(channel: channel);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns true when native channel reports Wi-Fi connected', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, equals('isWifiConnected'));
            return true;
          });

      expect(await service.isWifiConnected(), isTrue);
    });

    test(
      'returns false on PlatformException or MissingPluginException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: 'UNAVAILABLE');
            });

        expect(await service.isWifiConnected(), isFalse);
      },
    );
  });
}
