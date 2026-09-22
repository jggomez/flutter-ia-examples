import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/classifier_repository.dart';
import '../../domain/repositories/history_repository.dart';

/// Composition root for the two repository abstractions the whole app is
/// built around.
///
/// Every feature view model MUST depend on [classifierRepositoryProvider]
/// / [historyRepositoryProvider] (or a use case built on top of them) —
/// never on `ClassifierRepositoryImpl`/`HistoryRepositoryImpl` directly, and
/// never on `package:camera` / `package:flutter_litert` / `package:hive`
/// types. This is what lets `ProviderContainer(overrides: [...])` swap in
/// fakes in tests without touching feature code.
///
/// TODO(flutter-implementer): override these with the real
/// `ClassifierRepositoryImpl` / `HistoryRepositoryImpl` instances (wiring
/// their own service/box dependencies) at app bootstrap, e.g. in `main.dart`
/// via `ProviderScope(overrides: [...])`, or by replacing the
/// `throw UnimplementedError()` bodies below once the concrete services
/// exist and are constructed here.
final classifierRepositoryProvider = Provider<ClassifierRepository>((ref) {
  throw UnimplementedError(
    'Override with ClassifierRepositoryImpl at app bootstrap, or with a '
    'fake in tests via ProviderContainer(overrides: [...]).',
  );
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  throw UnimplementedError(
    'Override with HistoryRepositoryImpl at app bootstrap, or with a fake '
    'in tests via ProviderContainer(overrides: [...]).',
  );
});
