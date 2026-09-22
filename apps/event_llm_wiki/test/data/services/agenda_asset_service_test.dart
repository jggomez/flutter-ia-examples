import 'package:event_llm_wiki/data/services/agenda_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `flutter test` serves real project assets declared in pubspec.yaml
  // through `rootBundle` with no platform channel/device involved, so this
  // exercises the real `rootBundle.loadString` wrapper against the real
  // bundled `assets/agenda.json` — no fake/mocking needed for this thin,
  // one-line service.
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loadAgendaJson returns the bundled assets/agenda.json contents',
    () async {
      final service = AgendaAssetServiceImpl();

      final json = await service.loadAgendaJson();

      expect(json, contains('"talks"'));
      expect(json, contains('talk-001'));
    },
  );

  test('loadAgendaJson throws when the asset path does not exist', () async {
    final service = AgendaAssetServiceImpl(assetPath: 'assets/missing.json');

    expect(service.loadAgendaJson(), throwsA(anything));
  });
}
