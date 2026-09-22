import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/agenda_repository.dart';
import '../../domain/repositories/chat_engine_repository.dart';
import '../../domain/repositories/chat_history_repository.dart';
import '../../domain/repositories/model_download_repository.dart';

/// Composition root for the four repository abstractions the whole app is
/// built around.
///
/// Every feature view model MUST depend on these providers (or a use case
/// built on top of them) — never on `*RepositoryImpl` directly, and never
/// on `package:flutter_litert_lm` / `package:hive` / `package:http` /
/// `package:path_provider` types. This is what lets
/// `ProviderContainer(overrides: [...])` swap in fakes in tests without
/// touching feature code. Mirrors `apps/rps_live`'s
/// `ui/providers/repository_providers.dart` convention exactly.
///
/// TODO(flutter-implementer): override these with the real
/// `*RepositoryImpl` instances (wiring their own service dependencies) at
/// app bootstrap in `main.dart` via `ProviderScope(overrides: [...])`, once
/// the concrete services/repositories exist.
final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  throw UnimplementedError(
    'Override with AgendaRepositoryImpl at app bootstrap, or with a fake '
    'in tests via ProviderContainer(overrides: [...]).',
  );
});

final chatEngineRepositoryProvider = Provider<ChatEngineRepository>((ref) {
  throw UnimplementedError(
    'Override with ChatEngineRepositoryImpl at app bootstrap, or with a '
    'fake in tests via ProviderContainer(overrides: [...]).',
  );
});

final chatHistoryRepositoryProvider = Provider<ChatHistoryRepository>((ref) {
  throw UnimplementedError(
    'Override with ChatHistoryRepositoryImpl at app bootstrap, or with a '
    'fake in tests via ProviderContainer(overrides: [...]).',
  );
});

final modelDownloadRepositoryProvider = Provider<ModelDownloadRepository>((
  ref,
) {
  throw UnimplementedError(
    'Override with ModelDownloadRepositoryImpl at app bootstrap, or with a '
    'fake in tests via ProviderContainer(overrides: [...]).',
  );
});
