import 'dart:io';

import '../../domain/models/budget_breakdown.dart';
import '../../domain/models/llm_engine_config.dart';
import '../../domain/models/model_download_state.dart';
import '../../domain/models/saved_trip.dart';
import '../agents/pocket_squad_agent_factory.dart';
import '../llm/litert_chat_driver.dart';
import '../services/app_storage_service.dart';
import '../services/model_download_service.dart';
import '../services/network_connectivity_service.dart';

/// Repository coordinating [ModelDownloadService], [NetworkConnectivityService],
/// [AppStorageService], and the shared [LiteRtChatDriver] singleton.
class PocketSquadRepository {
  const PocketSquadRepository({
    required this.downloadService,
    required this.connectivityService,
    required this.storageService,
    required this.chatDriver,
  });

  final ModelDownloadService downloadService;
  final NetworkConnectivityService connectivityService;
  final AppStorageService storageService;
  final LiteRtChatDriver chatDriver;

  /// Checks whether the on-device `.litertlm` model exists on disk (`>= 400 MB`),
  /// queries Wi-Fi connectivity via `MethodChannel`, and initializes [chatDriver]
  /// if the model is present.
  Future<ModelDownloadState> checkModelReadiness({int? minBytes}) async {
    final isWifi = await connectivityService.isWifiConnected();
    final existingPath = await downloadService.findExistingModelPath(
      minBytes: minBytes,
    );

    if (existingPath != null) {
      final length = await File(existingPath).length();
      await chatDriver.initialize(modelFilePath: existingPath);
      return ModelDownloadState(
        phase: ModelDownloadPhase.ready,
        downloadedBytes: length,
        totalBytes: length,
        progress: 1.0,
        isOnWifi: isWifi,
        modelFilePath: existingPath,
      );
    }

    if (!isWifi) {
      return const ModelDownloadState(
        phase: ModelDownloadPhase.wifiRequired,
        isOnWifi: false,
      );
    }

    return const ModelDownloadState(
      phase: ModelDownloadPhase.notDownloaded,
      isOnWifi: true,
    );
  }

  /// Streams model download progress and initializes [chatDriver] once complete.
  Stream<ModelDownloadState> downloadAndInitializeModel({
    String? hfToken,
    String? url,
    int? minBytes,
  }) async* {
    await for (final state in downloadService.downloadModel(
      hfToken: hfToken,
      url: url,
      minBytes: minBytes,
    )) {
      if (state.isReady && state.modelFilePath != null) {
        await chatDriver.initialize(modelFilePath: state.modelFilePath!);
      }
      yield state;
    }
  }

  /// Loads all persisted [SavedTrip] dossiers from [storageService].
  Future<List<SavedTrip>> loadSavedTrips() => storageService.loadSavedTrips();

  /// Persists a [SavedTrip] dossier in [storageService].
  Future<List<SavedTrip>> saveTrip(SavedTrip trip) =>
      storageService.saveTrip(trip);

  /// Deletes a [SavedTrip] dossier by [tripId].
  Future<List<SavedTrip>> deleteTrip(String tripId) =>
      storageService.deleteTrip(tripId);

  /// Loads the persisted [LlmEngineConfig].
  Future<LlmEngineConfig> loadEngineConfig() =>
      storageService.loadEngineConfig();

  /// Persists the active [LlmEngineConfig].
  Future<void> saveEngineConfig(LlmEngineConfig config) =>
      storageService.saveEngineConfig(config);

  /// Builds the 3-agent [PocketSquadBundle] for the given [config].
  PocketSquadBundle createSquadBundle({
    required LlmEngineConfig config,
    void Function(String agentName, String status)? onAgentStepUpdate,
    void Function(BudgetBreakdown breakdown)? onBudgetCalculated,
    void Function(SavedTrip trip)? onTripSaved,
    void Function(String agentHint, String stage)? onTurnEvent,
  }) {
    return PocketSquadAgentFactory.create(
      config: config,
      driver: chatDriver,
      storageService: storageService,
      onAgentStepUpdate: onAgentStepUpdate,
      onBudgetCalculated: onBudgetCalculated,
      onTripSaved: onTripSaved,
      onTurnEvent: onTurnEvent,
    );
  }
}
