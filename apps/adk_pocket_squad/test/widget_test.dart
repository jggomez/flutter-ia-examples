import 'package:adk_pocket_squad/data/llm/litert_chat_driver.dart';
import 'package:adk_pocket_squad/data/services/app_storage_service.dart';
import 'package:adk_pocket_squad/data/services/model_download_service.dart';
import 'package:adk_pocket_squad/data/services/network_connectivity_service.dart';
import 'package:adk_pocket_squad/main.dart';
import 'package:adk_pocket_squad/ui/providers/app_providers.dart';
import 'package:adk_pocket_squad/ui/screens/pocket_squad_workspace_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestWifiService implements NetworkConnectivityService {
  @override
  Future<bool> isWifiConnected() async => true;
}

class _TestModelDownloadService extends ModelDownloadService {
  @override
  Future<String?> findExistingModelPath({int? minBytes}) async =>
      '/tmp/models/${ModelDownloadService.modelFileName}';
}

void main() {
  testWidgets(
    'PocketSquadApp smoke test boots into workspace when model exists',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final storage = AppStorageService(sharedPreferences: prefs);
      final downloadService = _TestModelDownloadService();
      final driver = FakeLiteRtChatDriver();
      addTearDown(driver.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appStorageServiceProvider.overrideWithValue(storage),
            networkConnectivityServiceProvider.overrideWithValue(
              _TestWifiService(),
            ),
            modelDownloadServiceProvider.overrideWithValue(downloadService),
            liteRtChatDriverProvider.overrideWithValue(driver),
          ],
          child: const PocketSquadApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PocketSquadWorkspaceScreen), findsOneWidget);
      expect(find.text('Pocket Squad'), findsOneWidget);
    },
  );
}
