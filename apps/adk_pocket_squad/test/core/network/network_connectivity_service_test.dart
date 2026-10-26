import 'package:adk_pocket_squad/data/services/network_connectivity_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkConnectivityServiceImpl', () {
    const channel = MethodChannel(
      'com.jggomez.flutterai.adk_pocket_squad/network',
    );
    const service = NetworkConnectivityServiceImpl(channel: channel);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns true when native channel reports Wi-Fi connected', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, equals('isWifiConnected'));
            return true;
          });

      expect(await service.isWifiConnected(), isTrue);
      expect(await service.isOnWifi(), isTrue);
    });

    test(
      'returns false when native channel reports Wi-Fi disconnected',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, equals('isWifiConnected'));
              return false;
            });

        expect(await service.isWifiConnected(), isFalse);
      },
    );

    test('returns false when native channel returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      expect(await service.isWifiConnected(), isFalse);
    });

    test(
      'returns false on PlatformException or MissingPluginException',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: 'UNAVAILABLE');
            });

        expect(await service.isWifiConnected(), isFalse);
      },
    );
  });
}
