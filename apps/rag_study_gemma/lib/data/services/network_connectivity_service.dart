import 'package:flutter/services.dart';

/// Abstraction for querying whether the device is currently connected to Wi-Fi
/// before downloading the dual `.litertlm` models (~686 MB total).
abstract interface class NetworkConnectivityService {
  /// Returns `true` when the device currently has an active Wi-Fi transport.
  Future<bool> isWifiConnected();
}

/// Real implementation backed by Android `ConnectivityManager` (`TRANSPORT_WIFI`)
/// via `MethodChannel('com.jggomez.flutterai.rag_study_gemma/network')`.
class NetworkConnectivityServiceImpl implements NetworkConnectivityService {
  const NetworkConnectivityServiceImpl({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.jggomez.flutterai.rag_study_gemma/network',
  );

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
}
