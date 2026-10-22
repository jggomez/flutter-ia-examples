import 'dart:io';

import 'package:event_gemma/data/services/app_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Fake `path_provider` platform implementation backed by a real temp
/// directory — no platform channel/device involved, matching PLAN.md
/// phase 7's "no real device storage" testing constraint.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory tempDir;
  late AppStorageServiceImpl service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('event_llm_wiki_storage');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    service = AppStorageServiceImpl();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'modelFilePath joins the app-support directory with modelFileName',
    () async {
      final path = await service.modelFilePath;

      expect(path, '${tempDir.path}/model.litertlm');
    },
  );

  test('modelPartFilePath is modelFilePath with a .part suffix', () async {
    final path = await service.modelPartFilePath;

    expect(path, '${tempDir.path}/model.litertlm.part');
  });

  test('modelFileExists is false when no file has been written', () async {
    expect(await service.modelFileExists(), isFalse);
  });

  test('modelFileExists is true once the model file is written', () async {
    final path = await service.modelFilePath;
    await File(path).writeAsBytes([1, 2, 3]);

    expect(await service.modelFileExists(), isTrue);
  });

  test('modelFileSizeBytes is null when the file does not exist', () async {
    expect(await service.modelFileSizeBytes(), isNull);
  });

  test('modelFileSizeBytes returns the real file size', () async {
    final path = await service.modelFilePath;
    await File(path).writeAsBytes(List.filled(1024, 0));

    expect(await service.modelFileSizeBytes(), 1024);
  });

  test('deletePartFileIfExists removes a leftover .part file', () async {
    final partPath = await service.modelPartFilePath;
    await File(partPath).writeAsBytes([1, 2, 3]);

    await service.deletePartFileIfExists();

    expect(File(partPath).existsSync(), isFalse);
  });

  test('deletePartFileIfExists is a no-op when no .part file exists', () async {
    await expectLater(service.deletePartFileIfExists(), completes);
  });

  test('renamePartFileToModelFile atomically moves .part into place', () async {
    final partPath = await service.modelPartFilePath;
    await File(partPath).writeAsBytes([1, 2, 3]);

    await service.renamePartFileToModelFile();

    expect(File(partPath).existsSync(), isFalse);
    expect(await service.modelFileExists(), isTrue);
  });

  test('appendToPartFile creates and appends to the .part file across '
      'multiple calls', () async {
    await service.appendToPartFile([1, 2, 3]);
    await service.appendToPartFile([4, 5]);
    await service.closePartFileWriter();

    final partPath = await service.modelPartFilePath;
    expect(await File(partPath).readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('closePartFileWriter is a no-op when appendToPartFile was never '
      'called', () async {
    await expectLater(service.closePartFileWriter(), completes);
  });

  test('a custom modelFileName is honored', () async {
    final custom = AppStorageServiceImpl(modelFileName: 'custom.litertlm');

    expect(await custom.modelFilePath, '${tempDir.path}/custom.litertlm');
  });
}
