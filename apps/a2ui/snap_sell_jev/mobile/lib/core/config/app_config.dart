import 'package:flutter/foundation.dart';

/// Runtime configuration resolved via `--dart-define` / `--dart-define-from-file`.
@immutable
class AppConfig {
  /// Creates an [AppConfig] with optional overrides.
  const AppConfig({this.baseUrl = agentBaseUrl, this.token = clientToken});

  /// Creates an [AppConfig] resolved from compile-time environment defines.
  const factory AppConfig.fromEnvironment() = AppConfig;

  /// Base URL of the Snap & Sell A2A / A2UI agent server.
  static const String agentBaseUrl = String.fromEnvironment(
    'AGENT_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Optional client token header for Cloud Run demo protection.
  static const String clientToken = String.fromEnvironment(
    'SNAP_SELL_CLIENT_TOKEN',
    defaultValue: '',
  );

  /// The A2UI v1.0 catalog id shared with the agent (`contracts/`).
  static const String snapSellCatalogId =
      'https://snap-sell.devhack.dev/a2ui/v1.0/snap_sell_catalog.json';

  /// Parsed [Uri] for the default agent server endpoint.
  static Uri get agentUri => Uri.parse(agentBaseUrl);

  /// Instance base URL for the agent server.
  final String baseUrl;

  /// Instance client token for the agent server.
  final String token;

  /// Parsed [Uri] for [baseUrl].
  Uri get uri => Uri.parse(baseUrl);
}
