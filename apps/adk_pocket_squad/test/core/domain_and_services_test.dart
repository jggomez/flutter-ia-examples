import 'dart:async';
import 'dart:io';

import 'package:adk_pocket_squad/data/services/app_storage_service.dart';
import 'package:adk_pocket_squad/data/services/model_download_service.dart';
import 'package:adk_pocket_squad/domain/models/budget_breakdown.dart';
import 'package:adk_pocket_squad/domain/models/llm_engine_config.dart';
import 'package:adk_pocket_squad/domain/models/model_download_state.dart';
import 'package:adk_pocket_squad/domain/models/saved_trip.dart';
import 'package:adk_pocket_squad/domain/models/squad_mission_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Domain Models', () {
    test('LlmEngineConfig defaults, copyWith, and JSON round-trip', () {
      const config = LlmEngineConfig();
      expect(config.mode, equals(LlmEngineMode.onDeviceLiteRt));
      expect(config.ollamaBaseUrl, equals('http://10.0.2.2:11434/v1'));
      expect(config.ollamaModel, equals('ollama_chat/gemma3:4b'));
      expect(config.onDeviceModelName, equals('gemma-4-E2B-it.litertlm'));

      final updated = config.copyWith(
        mode: LlmEngineMode.lanOllama,
        ollamaBaseUrl: 'http://192.168.1.50:11434/v1',
      );
      final restored = LlmEngineConfig.fromJson(updated.toJson());
      expect(restored.mode, equals(LlmEngineMode.lanOllama));
      expect(restored.ollamaBaseUrl, equals('http://192.168.1.50:11434/v1'));
      expect(restored.ollamaModel, equals('ollama_chat/gemma3:4b'));
      expect(restored.onDeviceModelName, equals('gemma-4-E2B-it.litertlm'));
    });

    test('BudgetBreakdown calculate, toJson, and fromJson round-trip', () {
      final breakdown = BudgetBreakdown.calculate(
        days: 4,
        lodgingPerNightUsd: 140,
        foodPerDayUsd: 60,
        activitiesTotalUsd: 200,
        targetCurrency: 'JPY',
        userBudgetUsd: 1200,
      );

      expect(breakdown.lodgingTotalUsd, equals(560));
      expect(breakdown.foodTotalUsd, equals(240));
      expect(breakdown.subtotalUsd, equals(1000));
      expect(breakdown.contingencyBufferUsd, equals(100));
      expect(breakdown.grandTotalUsd, equals(1100));
      expect(breakdown.budgetDeltaUsd, equals(100));
      expect(breakdown.withinBudget, isTrue);

      final restored = BudgetBreakdown.fromJson(breakdown.toJson());
      expect(restored.grandTotalUsd, equals(1100));
      expect(restored.targetCurrency, equals('JPY'));
      expect(restored.withinBudget, isTrue);
    });

    test('SavedTrip toJson and fromJson round-trip', () {
      final trip = SavedTrip(
        id: 'trip-kyoto-1',
        destination: 'Kyoto, Japan',
        days: 4,
        itinerarySummary:
            '4-day cultural exploration of Higashiyama and Arashiyama.',
        packingChecklist: const ['JR Pass', 'Power adapter', 'Walking shoes'],
        budgetBreakdown: BudgetBreakdown.calculate(
          days: 4,
          lodgingPerNightUsd: 140,
          foodPerDayUsd: 60,
          activitiesTotalUsd: 200,
          targetCurrency: 'JPY',
          userBudgetUsd: 1200,
        ),
        conciergeNotes: 'Book tea ceremony 2 weeks ahead.',
        createdAt: DateTime.utc(2026, 10, 25, 12, 0),
        engineLabel: 'On-Device Gemma 4 E2B (LiteRT-LM)',
      );

      final restored = SavedTrip.fromJson(trip.toJson());
      expect(restored.id, equals('trip-kyoto-1'));
      expect(restored.destination, equals('Kyoto, Japan'));
      expect(restored.days, equals(4));
      expect(restored.packingChecklist, hasLength(3));
      expect(restored.budgetBreakdown.grandTotalUsd, equals(1100));
      expect(restored.engineLabel, equals('On-Device Gemma 4 E2B (LiteRT-LM)'));
    });

    test('ModelDownloadState copyWith updates fields accurately', () {
      const initial = ModelDownloadState();
      expect(initial.phase, equals(ModelDownloadPhase.checking));

      final downloading = initial.copyWith(
        phase: ModelDownloadPhase.downloading,
        downloadedBytes: 512,
        totalBytes: 1024,
        progress: 0.5,
        isOnWifi: true,
      );
      expect(downloading.phase, equals(ModelDownloadPhase.downloading));
      expect(downloading.progress, equals(0.5));
      expect(downloading.isDownloading, isTrue);
    });

    test('SquadMissionPreset exposes 4 curated travel presets', () {
      expect(SquadMissionPreset.defaultPresets, hasLength(4));
      final titles = SquadMissionPreset.defaultPresets
          .map((preset) => preset.title)
          .toList();
      expect(
        titles,
        containsAll(<String>[
          'Kyoto Cultural Odyssey',
          'Cartagena Caribbean Escape',
          'Lisbon Culinary & Tram Tour',
          'Reykjavik Northern Lights',
        ]),
      );
    });
  });

  group('ModelDownloadService', () {
    late Directory docsDir;
    late Directory supportDir;

    setUp(() async {
      docsDir = await Directory.systemTemp.createTemp('pocket_squad_docs_');
      supportDir = await Directory.systemTemp.createTemp(
        'pocket_squad_support_',
      );
    });

    tearDown(() async {
      if (await docsDir.exists()) {
        await docsDir.delete(recursive: true);
      }
      if (await supportDir.exists()) {
        await supportDir.delete(recursive: true);
      }
    });

    test('detects pre-existing model in either documents or support/models directory', () async {
      final modelsSubDir = Directory('${supportDir.path}/models');
      await modelsSubDir.create(recursive: true);
      final supportModelFile = File(
        '${modelsSubDir.path}/${ModelDownloadService.modelFileName}',
      );
      await supportModelFile.writeAsBytes(List<int>.filled(16, 1));

      final service = ModelDownloadService(
        documentsDirectoryProvider: () async => docsDir,
        supportDirectoryProvider: () async => supportDir,
        minValidBytesOverride: 8,
      );

      expect(await service.isModelDownloaded(), isTrue);
      expect(
        await service.resolveModelFilePath(),
        equals(supportModelFile.path),
      );
    });

    test('strips Authorization header on cross-host HuggingFace CDN redirect and writes atomically via .part', () async {
      final client = _RecordingHttpClient((request) async {
        if (request.url.host == 'huggingface.co') {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            302,
            headers: {
              'location': 'https://cdn-lfs.huggingface.co/repos/gemma-4-E2B-it.litertlm',
            },
          );
        }
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            [1, 2, 3, 4],
            [5, 6, 7, 8],
          ]),
          200,
          contentLength: 8,
        );
      });

      final service = ModelDownloadService(
        client: client,
        documentsDirectoryProvider: () async => docsDir,
        supportDirectoryProvider: () async => supportDir,
        minValidBytesOverride: 8,
      );

      final states = await service
          .downloadModel(hfToken: 'hf_secret_123')
          .toList();

      expect(states.last.phase, equals(ModelDownloadPhase.ready));
      expect(client.recordedRequests, hasLength(2));
      expect(
        client.recordedRequests[0].headers['Authorization'],
        equals('Bearer hf_secret_123'),
      );
      expect(
        client.recordedRequests[1].headers.containsKey('Authorization'),
        isFalse,
      );

      final targetPath = states.last.modelFilePath!;
      expect(await File(targetPath).exists(), isTrue);
      expect(await File('$targetPath.part').exists(), isFalse);
    });
  });

  group('AppStorageService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'persists and restores SavedTrips, LlmEngineConfig, and HF token',
      () async {
        final storage = AppStorageService();

        const config = LlmEngineConfig(
          mode: LlmEngineMode.lanOllama,
          ollamaBaseUrl: 'http://192.168.0.10:11434/v1',
        );
        await storage.saveEngineConfig(config);
        final loadedConfig = await storage.loadEngineConfig();
        expect(loadedConfig.mode, equals(LlmEngineMode.lanOllama));
        expect(
          loadedConfig.ollamaBaseUrl,
          equals('http://192.168.0.10:11434/v1'),
        );

        final trip = SavedTrip(
          id: 'trip-1',
          destination: 'Lisbon, Portugal',
          days: 5,
          itinerarySummary: 'Alfama & Belem culinary route.',
          packingChecklist: const ['Comfortable shoes', 'Sunglasses'],
          budgetBreakdown: BudgetBreakdown.calculate(
            days: 5,
            lodgingPerNightUsd: 130,
            foodPerDayUsd: 55,
            activitiesTotalUsd: 180,
            targetCurrency: 'EUR',
            userBudgetUsd: 1500,
          ),
          conciergeNotes: 'Ride Tram 28 early morning.',
          createdAt: DateTime.utc(2026, 10, 25),
          engineLabel: 'On-Device Gemma 4 E2B (LiteRT-LM)',
        );
        await storage.saveTrip(trip);
        final trips = await storage.loadSavedTrips();
        expect(trips, hasLength(1));
        expect(trips.first.destination, equals('Lisbon, Portugal'));

        await storage.saveHfToken('hf_abc');
        expect(await storage.loadHfToken(), equals('hf_abc'));
      },
    );
  });
}
