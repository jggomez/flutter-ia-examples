import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../data/repositories/image_capture_repository_impl.dart';
import '../../data/repositories/selling_agent_repository_impl.dart';
import '../../domain/repositories/image_capture_repository.dart';
import '../../domain/repositories/selling_agent_repository.dart';
import '../catalog/snap_sell_catalog.dart';

/// Provides compile-time [AppConfig] resolved from `--dart-define` / `--dart-define-from-file`.
final Provider<AppConfig> appConfigProvider = Provider<AppConfig>((Ref ref) {
  return AppConfig.fromEnvironment();
});

/// Provides the [ImageCaptureRepository] implementation.
final Provider<ImageCaptureRepository> imageCaptureRepositoryProvider =
    Provider<ImageCaptureRepository>((Ref ref) {
      return ImageCaptureRepositoryImpl();
    });

/// Alias matching prompt naming (`imageCaptureServiceProvider`).
final Provider<ImageCaptureRepository> imageCaptureServiceProvider =
    imageCaptureRepositoryProvider;

/// Provides the [SellingAgentRepository] (`A2uiAgentService`) implementation.
final Provider<SellingAgentRepository> sellingAgentRepositoryProvider =
    Provider<SellingAgentRepository>((Ref ref) {
      final AppConfig config = ref.watch(appConfigProvider);
      final ImageCaptureRepository captureRepository = ref.watch(
        imageCaptureRepositoryProvider,
      );
      final SellingAgentRepositoryImpl repository = SellingAgentRepositoryImpl(
        config: config,
        catalog: buildSnapSellCatalog(imageCaptureService: captureRepository),
      );
      ref.onDispose(repository.dispose);
      return repository;
    });

/// Alias matching prompt naming (`a2uiAgentServiceProvider`).
final Provider<SellingAgentRepository> a2uiAgentServiceProvider =
    sellingAgentRepositoryProvider;
