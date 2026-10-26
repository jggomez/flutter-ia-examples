import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/llm/litert_chat_driver.dart';
import '../../data/services/app_storage_service.dart';
import '../../data/services/model_download_service.dart';
import '../../data/services/network_connectivity_service.dart';
import '../../domain/models/llm_engine_config.dart';
import '../../domain/models/model_download_state.dart';

/// Manages the readiness gate, Wi-Fi verification via `MethodChannel`,
/// Hugging Face token storage, and atomic `.part` download progress for
/// the 2.58 GB `gemma-4-E2B-it.litertlm` model.
class ModelDownloadViewModel extends ChangeNotifier {
  ModelDownloadViewModel({
    required this.downloadService,
    required this.connectivityService,
    required this.storageService,
    required this.chatDriver,
    bool autoCheck = true,
  }) {
    if (autoCheck) {
      unawaited(checkReadiness());
    }
  }

  final ModelDownloadService downloadService;
  final NetworkConnectivityService connectivityService;
  final AppStorageService storageService;
  final LiteRtChatDriver chatDriver;

  ModelDownloadState _state = const ModelDownloadState();
  LlmEngineConfig _engineConfig = const LlmEngineConfig();
  String? _hfToken;
  StreamSubscription<ModelDownloadState>? _downloadSubscription;
  bool _isDisposed = false;

  ModelDownloadState get state => _state;
  LlmEngineConfig get engineConfig => _engineConfig;
  String? get hfToken => _hfToken;
  bool get isReady => _state.isReady;

  /// Verifies Wi-Fi connectivity and checks whether the on-device `.litertlm`
  /// model (`>= 400 MB`) already exists on disk.
  ///
  /// If present, immediately transitions to [ModelDownloadPhase.ready] and
  /// initializes [LiteRtChatDriver].
  Future<void> checkReadiness() async {
    _updateState(
      _state.copyWith(
        phase: ModelDownloadPhase.checking,
        clearErrorMessage: true,
      ),
    );

    try {
      _hfToken = await storageService.loadHfToken();
      _engineConfig = await storageService.loadEngineConfig();
      final isWifi = await connectivityService.isWifiConnected();
      final existingPath = await downloadService.findExistingModelPath();

      if (existingPath != null) {
        final file = File(existingPath);
        final fileLength = file.existsSync() ? file.lengthSync() : 0;
        await chatDriver.initialize(modelFilePath: existingPath);
        _updateState(
          ModelDownloadState(
            phase: ModelDownloadPhase.ready,
            downloadedBytes: fileLength,
            totalBytes: fileLength,
            progress: 1.0,
            isOnWifi: isWifi,
            modelFilePath: existingPath,
          ),
        );
        return;
      }

      if (_engineConfig.mode == LlmEngineMode.lanOllama) {
        _updateState(
          ModelDownloadState(
            phase: ModelDownloadPhase.ready,
            downloadedBytes: 0,
            totalBytes: 0,
            progress: 1.0,
            isOnWifi: isWifi,
          ),
        );
        return;
      }

      if (!isWifi) {
        _updateState(
          const ModelDownloadState(
            phase: ModelDownloadPhase.wifiRequired,
            isOnWifi: false,
          ),
        );
        return;
      }

      _updateState(
        const ModelDownloadState(
          phase: ModelDownloadPhase.notDownloaded,
          isOnWifi: true,
        ),
      );
    } catch (error) {
      _updateState(
        _state.copyWith(
          phase: ModelDownloadPhase.error,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Saves or clears the optional Hugging Face access token.
  Future<void> saveHfToken(String? token) async {
    _hfToken = token?.trim().isEmpty == true ? null : token?.trim();
    await storageService.saveHfToken(_hfToken);
    _safeNotify();
  }

  /// Starts streaming the 2.58 GB `.litertlm` model download after verifying
  /// Wi-Fi connectivity via `NetworkConnectivityService.isWifiConnected()`.
  Future<void> startDownload({
    String? customToken,
    bool allowCellularOverride = false,
  }) async {
    if (_state.isDownloading) return;

    if (customToken != null) {
      await saveHfToken(customToken);
    }

    final isWifi = await connectivityService.isWifiConnected();
    if (!isWifi && !allowCellularOverride) {
      _updateState(
        _state.copyWith(
          phase: ModelDownloadPhase.wifiRequired,
          isOnWifi: false,
          errorMessage: 'Connect to Wi-Fi before downloading the 2.58 GB Gemma 4 E2B model.',
        ),
      );
      return;
    }

    await _downloadSubscription?.cancel();
    _updateState(
      ModelDownloadState(
        phase: ModelDownloadPhase.downloading,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0.0,
        isOnWifi: isWifi,
      ),
    );

    final completer = Completer<void>();
    _downloadSubscription = downloadService
        .downloadModel(hfToken: _hfToken)
        .listen(
          (progressState) async {
            if (progressState.phase == ModelDownloadPhase.ready &&
                progressState.modelFilePath != null) {
              try {
                await chatDriver.initialize(
                  modelFilePath: progressState.modelFilePath!,
                );
              } catch (error) {
                _updateState(
                  progressState.copyWith(
                    phase: ModelDownloadPhase.error,
                    errorMessage:
                        'Model downloaded, but LiteRT-LM initialization failed: $error',
                  ),
                );
                if (!completer.isCompleted) {
                  completer.complete();
                }
                return;
              }
            }
            _updateState(progressState.copyWith(isOnWifi: isWifi));
          },
          onError: (Object error) {
            _updateState(
              _state.copyWith(
                phase: ModelDownloadPhase.error,
                isOnWifi: isWifi,
                errorMessage: error.toString(),
              ),
            );
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          cancelOnError: true,
        );

    await completer.future;
  }

  /// Switches the active LLM engine configuration (e.g., to LAN Ollama mode).
  Future<void> updateEngineConfig(LlmEngineConfig config) async {
    _engineConfig = config;
    await storageService.saveEngineConfig(config);
    if (config.mode == LlmEngineMode.lanOllama) {
      final isWifi = await connectivityService.isWifiConnected();
      _updateState(
        _state.copyWith(
          phase: ModelDownloadPhase.ready,
          isOnWifi: isWifi,
          clearErrorMessage: true,
        ),
      );
    } else {
      await checkReadiness();
    }
  }

  void _updateState(ModelDownloadState next) {
    _state = next;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _downloadSubscription?.cancel();
    super.dispose();
  }
}
