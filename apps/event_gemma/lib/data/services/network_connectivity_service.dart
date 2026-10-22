import 'package:flutter/services.dart';

/// Abstraction for querying whether the mobile device is currently connected
/// to a Wi-Fi network before initiating the ~529 MB `.litertlm` model download.
abstract class NetworkConnectivityService {
  /// Returns `true` when the device currently has an active Wi-Fi transport.
  Future<bool> isWifiConnected();
}

/// Real implementation backed by the app's native connectivity MethodChannel
/// (`MainActivity.kt` on Android via `ConnectivityManager` +
/// `NetworkCapabilities.TRANSPORT_WIFI`).
class NetworkConnectivityServiceImpl implements NetworkConnectivityService {
  const NetworkConnectivityServiceImpl({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.jggomez.flutterai.event_gemma/connectivity',
  );

  final MethodChannel _channel;

  @override
  Future<bool> isWifiConnected() async {
    try {
      final result = await _channel.invokeMethod<bool>('isWifiConnected');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
