import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/llm/litert_chat_driver.dart';
import '../../data/services/app_storage_service.dart';
import '../../data/services/model_download_service.dart';
import '../../data/services/network_connectivity_service.dart';
import '../view_models/model_download_view_model.dart';
import '../view_models/pocket_squad_view_model.dart';

/// Optional pre-initialized [SharedPreferences] instance injected at startup or tests.
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

/// Provides the local [AppStorageService] backed by `SharedPreferences`.
final appStorageServiceProvider = Provider<AppStorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppStorageService(sharedPreferences: prefs);
});

/// Provides the native Android Wi-Fi `MethodChannel` connectivity service.
final networkConnectivityServiceProvider = Provider<NetworkConnectivityService>(
  (ref) => const NetworkConnectivityServiceImpl(),
);

/// Provides the atomic `.part` `.litertlm` model download service.
final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  return ModelDownloadService();
});

/// Provides the shared singleton [LiteRtChatDriver] for on-device Gemma 4 E2B IT.
final liteRtChatDriverProvider = Provider<LiteRtChatDriver>((ref) {
  final driver = LiteRtChatDriverImpl();
  ref.onDispose(driver.dispose);
  return driver;
});

/// Provides the [ModelDownloadViewModel] readiness gate controller.
final modelDownloadViewModelProvider = Provider<ModelDownloadViewModel>((ref) {
  final vm = ModelDownloadViewModel(
    downloadService: ref.watch(modelDownloadServiceProvider),
    connectivityService: ref.watch(networkConnectivityServiceProvider),
    storageService: ref.watch(appStorageServiceProvider),
    chatDriver: ref.watch(liteRtChatDriverProvider),
  );
  ref.onDispose(vm.dispose);
  return vm;
});

/// Provides the [PocketSquadViewModel] workspace and 3-agent pipeline controller.
final pocketSquadViewModelProvider = Provider<PocketSquadViewModel>((ref) {
  final downloadVm = ref.watch(modelDownloadViewModelProvider);
  final vm = PocketSquadViewModel(
    chatDriver: ref.watch(liteRtChatDriverProvider),
    storageService: ref.watch(appStorageServiceProvider),
    connectivityService: ref.watch(networkConnectivityServiceProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
    initialEngineConfig: downloadVm.engineConfig,
  );
  ref.onDispose(vm.dispose);
  return vm;
});
