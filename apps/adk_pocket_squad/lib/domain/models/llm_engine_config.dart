/// Execution mode for the Pocket Squad multi-agent LLM runtime.
enum LlmEngineMode {
  /// 100% standalone on-device inference via `flutter_edge_ai` + LiteRT-LM FFI.
  onDeviceLiteRt,

  /// Optional LAN inference via OpenAI-compatible Ollama / LM Studio endpoint.
  lanOllama;

  /// Human-readable label for UI badges and trip attribution.
  String get label => switch (this) {
    LlmEngineMode.onDeviceLiteRt => 'On-Device Gemma 4 E2B (LiteRT-LM)',
    LlmEngineMode.lanOllama => 'Local LAN Ollama (LiteLlm)',
  };

  /// Compact badge label for status bars.
  String get shortLabel => switch (this) {
    LlmEngineMode.onDeviceLiteRt => 'On-Device LiteRT',
    LlmEngineMode.lanOllama => 'LAN Ollama',
  };

  bool get isOnDevice => this == LlmEngineMode.onDeviceLiteRt;
}

/// Configuration for the active LLM backend powering the `SequentialAgent` squad.
class LlmEngineConfig {
  const LlmEngineConfig({
    this.mode = LlmEngineMode.onDeviceLiteRt,
    this.ollamaBaseUrl = defaultOllamaBaseUrl,
    this.ollamaModel = defaultOllamaModel,
    this.onDeviceModelName = defaultOnDeviceModelName,
  });

  static const String defaultOllamaBaseUrl = 'http://10.0.2.2:11434/v1';
  static const String defaultOllamaModel = 'ollama_chat/gemma3:4b';
  static const String defaultOnDeviceModelName = 'gemma-4-E2B-it.litertlm';

  final LlmEngineMode mode;
  final String ollamaBaseUrl;
  final String ollamaModel;
  final String onDeviceModelName;

  bool get isOnDevice => mode == LlmEngineMode.onDeviceLiteRt;

  String get engineLabel => switch (mode) {
    LlmEngineMode.onDeviceLiteRt => 'On-Device Gemma 4 E2B (LiteRT-LM)',
    LlmEngineMode.lanOllama => 'LAN Ollama ($ollamaModel)',
  };

  LlmEngineConfig copyWith({
    LlmEngineMode? mode,
    String? ollamaBaseUrl,
    String? ollamaModel,
    String? onDeviceModelName,
  }) {
    return LlmEngineConfig(
      mode: mode ?? this.mode,
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      onDeviceModelName: onDeviceModelName ?? this.onDeviceModelName,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode.name,
      'ollamaBaseUrl': ollamaBaseUrl,
      'ollamaModel': ollamaModel,
      'onDeviceModelName': onDeviceModelName,
    };
  }

  factory LlmEngineConfig.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode'] as String?;
    final parsedMode = LlmEngineMode.values.firstWhere(
      (value) => value.name == rawMode,
      orElse: () => LlmEngineMode.onDeviceLiteRt,
    );
    return LlmEngineConfig(
      mode: parsedMode,
      ollamaBaseUrl:
          (json['ollamaBaseUrl'] as String?)?.trim().isNotEmpty == true
          ? (json['ollamaBaseUrl'] as String).trim()
          : defaultOllamaBaseUrl,
      ollamaModel: (json['ollamaModel'] as String?)?.trim().isNotEmpty == true
          ? (json['ollamaModel'] as String).trim()
          : defaultOllamaModel,
      onDeviceModelName:
          (json['onDeviceModelName'] as String?)?.trim().isNotEmpty == true
          ? (json['onDeviceModelName'] as String).trim()
          : defaultOnDeviceModelName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LlmEngineConfig &&
        other.mode == mode &&
        other.ollamaBaseUrl == ollamaBaseUrl &&
        other.ollamaModel == ollamaModel &&
        other.onDeviceModelName == onDeviceModelName;
  }

  @override
  int get hashCode =>
      Object.hash(mode, ollamaBaseUrl, ollamaModel, onDeviceModelName);
}
