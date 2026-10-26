import 'package:flutter/services.dart';

/// Abstraction for querying whether the device is currently connected to Wi-Fi
/// before downloading the 2.58 GB `.litertlm` model or probing LAN Ollama.
abstract interface class NetworkConnectivityService {
  /// Returns `true` when the device currently has an active Wi-Fi transport.
  Future<bool> isWifiConnected();
}

/// Convenience extension aliasing [NetworkConnectivityService.isWifiConnected].
extension NetworkConnectivityServiceX on NetworkConnectivityService {
  /// Alias for [isWifiConnected] used by readiness gates.
  Future<bool> isOnWifi() => isWifiConnected();
}

/// Real implementation backed by Android `ConnectivityManager` (`TRANSPORT_WIFI`)
/// via `MethodChannel('com.jggomez.flutterai.adk_pocket_squad/network')`.
class NetworkConnectivityServiceImpl implements NetworkConnectivityService {
  const NetworkConnectivityServiceImpl({MethodChannel? channel})
    : _channel = channel ?? defaultChannel;

  static const String channelName =
      'com.jggomez.flutterai.adk_pocket_squad/network';

  static const MethodChannel defaultChannel = MethodChannel(channelName);

  final MethodChannel _channel;

  @override
  Future<bool> isWifiConnected() async {
    try {
      final result = await _channel.invokeMethod<bool>('isWifiConnected');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Alias for [isWifiConnected] matching ADR 0002 method naming.
  Future<bool> isOnWifi() => isWifiConnected();
}
