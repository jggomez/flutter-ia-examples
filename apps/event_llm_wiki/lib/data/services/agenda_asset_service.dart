import 'package:flutter/services.dart' show rootBundle;

/// Thin wrapper around `rootBundle.loadString` for `assets/agenda.json`.
///
/// Abstracted (rather than calling `rootBundle` directly inside
/// `AgendaRepositoryImpl`) so tests can substitute a
/// `FakeAgendaAssetService` returning a canned JSON string with no Flutter
/// asset bundle involved.
abstract class AgendaAssetService {
  /// Raw JSON text of the bundled agenda asset.
  ///
  /// Throws if the asset is missing — `AgendaRepositoryImpl` is responsible
  /// for wrapping that into `AgendaLoadException`.
  Future<String> loadAgendaJson();
}

/// Real implementation backed by `rootBundle`.
class AgendaAssetServiceImpl implements AgendaAssetService {
  AgendaAssetServiceImpl({this.assetPath = 'assets/agenda.json'});

  final String assetPath;

  @override
  Future<String> loadAgendaJson() => rootBundle.loadString(assetPath);
}
