import 'dart:async';
import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'on_device_litert_gemma_llm.dart';

/// Shared singleton contract wrapping `flutter_edge_ai` + `flutter_edge_ai_litertlm`
/// (`gemma-4-E2B-it.litertlm`, `ModelType.gemma4`, `PreferredBackend.cpu`).
///
/// All three specialist agents in the `SequentialAgent` pipeline reuse the same
/// resident model weights in RAM (~0.8 GB `mmap` working set) by resetting the
/// per-turn `InferenceChat` session rather than reloading model weights.
abstract interface class LiteRtChatDriver {
  /// Whether the underlying LiteRT-LM model is loaded and ready for inference.
  bool get isInitialized;

  /// Absolute file path of the currently loaded `.litertlm` artifact, if any.
  String? get activeModelPath;

  /// Initializes the LiteRT-LM runtime and loads [modelFilePath] on CPU (`mmap`).
  Future<void> initialize({required String modelFilePath});

  /// Generates a single serialized completion turn using a fresh `InferenceChat`
  /// session so the KV cache never overflows across multi-agent turns.
  Future<String> generateCompletion({
    required String prompt,
    String? systemInstruction,
    int maxOutputTokens = 320,
  });

  /// Closes the active chat session and releases the native `InferenceModel`.
  Future<void> dispose();
}

/// Production on-device implementation backed by `FlutterEdgeAi` and
/// `LiteRtLmEngine` (`ModelType.gemma4`, `PreferredBackend.cpu`).
class LiteRtChatDriverImpl implements LiteRtChatDriver {
  LiteRtChatDriverImpl({this.backendFallback = true});

  static const int maxResponseChars = 2600;

  static const String _defaultSystemInstruction =
      'You are a concise, accurate travel and budget specialist in the '
      'Pocket Squad multi-agent concierge. Never repeat sentences or phrases.';

  static final RegExp _whitespacePattern = RegExp(r'\s+');
  static final RegExp _bracketTagPattern = RegExp(r'\[[^\]]*\]');

  final bool backendFallback;

  bool _runtimeInitialized = false;
  InferenceModel? _llmModel;
  InferenceChat? _chat;
  String? _activeModelPath;
  Future<void>? _activeTurn;

  @override
  bool get isInitialized => _llmModel != null;

  @override
  String? get activeModelPath => _activeModelPath;

  Future<void> _ensureRuntimeInitialized() async {
    if (_runtimeInitialized) return;
    await FlutterEdgeAi.initialize(
      inferenceEngines: [LiteRtLmEngine(backendFallback: backendFallback)],
    );
    _runtimeInitialized = true;
  }

  @override
  Future<void> initialize({required String modelFilePath}) async {
    if (_llmModel != null && _activeModelPath == modelFilePath) {
      return;
    }

    await _runExclusively(() async {
      if (_llmModel != null && _activeModelPath == modelFilePath) {
        return;
      }

      await _closeChatAndModel();
      await _ensureRuntimeInitialized();

      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(modelFilePath).install();

      _llmModel = await FlutterEdgeAi.getActiveModel(
        maxTokens: 2048,
        preferredBackend: PreferredBackend.cpu,
      );
      _activeModelPath = modelFilePath;
    });
  }

  @override
  Future<String> generateCompletion({
    required String prompt,
    String? systemInstruction,
    int maxOutputTokens = 320,
  }) {
    return _runExclusively<String>(() async {
      final model = _llmModel;
      if (model == null) {
        throw StateError(
          'LiteRtChatDriverImpl.initialize() must complete before generateCompletion().',
        );
      }

      final previousChat = _chat;
      _chat = null;
      if (previousChat != null) {
        await previousChat.close();
      }

      final effectiveInstruction =
          (systemInstruction != null && systemInstruction.trim().isNotEmpty)
          ? systemInstruction.trim()
          : _defaultSystemInstruction;

      final chat = await model.createChat(
        systemInstruction: effectiveInstruction,
        temperature: 0.3,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: maxOutputTokens,
        enableThinking: false,
      );
      _chat = chat;

      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      final accumulated = StringBuffer();

      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse && response.token.isNotEmpty) {
          final candidate = '$accumulated${response.token}';
          if (candidate.length > maxResponseChars ||
              hasRepetitionLoop(candidate)) {
            break;
          }
          accumulated.write(response.token);
        }
      }

      return accumulated.toString().trim();
    });
  }

  Future<T> _runExclusively<T>(Future<T> Function() action) async {
    while (_activeTurn != null) {
      try {
        await _activeTurn;
      } catch (_) {}
    }
    final completer = Completer<void>();
    _activeTurn = completer.future;
    try {
      return await action();
    } finally {
      _activeTurn = null;
      completer.complete();
    }
  }

  Future<void> _closeChatAndModel() async {
    final chat = _chat;
    _chat = null;
    if (chat != null) {
      try {
        await chat.close();
      } catch (_) {}
    }

    final model = _llmModel;
    _llmModel = null;
    _activeModelPath = null;
    if (model != null) {
      try {
        await model.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    await _runExclusively(_closeChatAndModel);
  }

  /// Deterministic guard detecting tandem phrase repetition or repeated
  /// 48-character clauses before exhausting context.
  static bool hasRepetitionLoop(String text) {
    final normalized = text.replaceAll(_whitespacePattern, ' ').trim();
    if (normalized.length < 24) return false;

    final withoutTags = normalized
        .replaceAll(_bracketTagPattern, '')
        .replaceAll(_whitespacePattern, ' ')
        .trim();

    if (_hasTandemSuffixLoop(normalized) || _hasTandemSuffixLoop(withoutTags)) {
      return true;
    }

    if (withoutTags.length >= 160) {
      final prefixEnd = withoutTags.length - 48;
      final tail = withoutTags.substring(prefixEnd);
      final priorText = withoutTags.substring(0, prefixEnd);
      final firstIdx = priorText.indexOf(tail);
      if (firstIdx != -1 && priorText.indexOf(tail, firstIdx + 1) != -1) {
        return true;
      }
    }

    return false;
  }

  static bool _hasTandemSuffixLoop(String s) {
    final n = s.length;
    for (var len = 8; len <= 80 && n >= 3 * len; len++) {
      final tail = s.substring(n - len, n);
      final mid = s.substring(n - 2 * len, n - len);
      if (mid == tail) {
        final head = s.substring(n - 3 * len, n - 2 * len);
        if (head == tail) {
          return true;
        }
      }
    }

    for (var len = 32; len <= 120 && n >= 2 * len; len++) {
      final tail = s.substring(n - len, n);
      if (s.substring(n - 2 * len, n - len) == tail) {
        return true;
      }
      if (n >= 2 * len + 1 &&
          s[n - len - 1] == ' ' &&
          s.substring(n - 2 * len - 1, n - len - 1) == tail) {
        return true;
      }
    }

    return false;
  }
}

/// Deterministic fake `LiteRtChatDriver` for automated tests and offline
/// simulation when native FFI binaries are unavailable.
class FakeLiteRtChatDriver implements LiteRtChatDriver {
  FakeLiteRtChatDriver({
    bool initiallyInitialized = false,
    String? initialModelPath,
  }) : _isInitialized = initiallyInitialized,
       _activeModelPath = initialModelPath;

  bool _isInitialized;
  String? _activeModelPath;
  final List<String> recordedPrompts = <String>[];

  @override
  bool get isInitialized => _isInitialized;

  @override
  String? get activeModelPath => _activeModelPath;

  @override
  Future<void> initialize({required String modelFilePath}) async {
    _isInitialized = true;
    _activeModelPath = modelFilePath;
  }

  @override
  Future<String> generateCompletion({
    required String prompt,
    String? systemInstruction,
    int maxOutputTokens = 320,
  }) async {
    recordedPrompts.add(prompt);
    final combined = '${systemInstruction ?? ''}\n$prompt';
    final lower = combined.toLowerCase();

    final destination = _inferDestination(combined);
    final days = _inferDays(combined);
    final currency = _inferCurrency(combined, destination);
    final userBudget = _inferUserBudget(combined, days);
    final lodgingPerNight = _inferLodging(destination);
    final foodPerDay = _inferFood(destination);
    final activitiesTotal = _inferActivities(destination, days);

    // CoordinatorAgent conversational intake turns
    if (lower.contains('coordinator_agent') ||
        lower.contains('travel intake')) {
      final isSpanish =
          lower.contains('language: spanish') ||
          RegExp(
            r'\b(hola|quiero|viajar|d[ií]as|presupuesto|kioto|tokio)\b',
            caseSensitive: false,
          ).hasMatch(lower);
      if (isSpanish) {
        return '¡Hola! Soy el **CoordinatorAgent** de tu Pocket Squad. '
            'Para activar al equipo de especialistas (**ScoutAgent**, **BudgetAuditorAgent** y **ConciergeAgent**), '
            'por favor compárteme los datos que faltan de tu viaje:\n'
            '- **Destino** (ciudad o país)\n'
            '- **Duración** (número de días o noches)\n'
            '- **Presupuesto total** (ej. `\$1,200 USD`)';
      }
      return 'Hello! I am the **CoordinatorAgent** of your Pocket Squad. '
          'Before I launch our 3-agent specialist pipeline (**ScoutAgent**, **BudgetAuditorAgent**, and **ConciergeAgent**), '
          'please share your remaining trip details:\n'
          '- **Destination** (city or country)\n'
          '- **Duration** (number of days or nights)\n'
          '- **Total Budget** (e.g., `\$1,200 USD`)';
    }

    // Tool-call generation turns
    if (lower.contains('<tool_call>') &&
        lower.contains('calculate_budget_math') &&
        !lower.contains('tool_result_summary')) {
      final payload = <String, dynamic>{
        'name': 'calculate_budget_math',
        'args': <String, dynamic>{
          'days': days,
          'lodging_per_night_usd': lodgingPerNight,
          'food_per_day_usd': foodPerDay,
          'activities_total_usd': activitiesTotal,
          'target_currency': currency,
          'user_budget_usd': userBudget,
        },
      };
      return '<tool_call>${jsonEncode(payload)}</tool_call>';
    }

    if (lower.contains('<tool_call>') &&
        lower.contains('save_trip_plan') &&
        !lower.contains('tool_result_summary')) {
      final payload = <String, dynamic>{
        'name': 'save_trip_plan',
        'args': <String, dynamic>{
          'destination': destination,
          'days': days,
          'itinerary_summary':
              '$days-day curated cultural, culinary, and neighborhood route across $destination.',
          'packing_checklist': <String>[
            'Passport & offline boarding passes',
            'Universal power adapter & portable battery',
            'Broken-in walking shoes for neighborhood exploration',
            'Light weatherproof layer & local transit card',
          ],
          'concierge_notes': 'Reserve popular dining and morning cultural entries 7-14 days ahead.',
          'lodging_per_night_usd': lodgingPerNight,
          'food_per_day_usd': foodPerDay,
          'activities_total_usd': activitiesTotal,
          'target_currency': currency,
          'user_budget_usd': userBudget,
        },
      };
      return '<tool_call>${jsonEncode(payload)}</tool_call>';
    }

    final isSpanish =
        lower.contains('respond in spanish') ||
        lower.contains('en español') ||
        lower.contains('language: spanish') ||
        RegExp(
          r'\b(hola|quiero|viajar|d[ií]as|presupuesto|kioto|tokio)\b',
          caseSensitive: false,
        ).hasMatch(lower);

    // Narrative generation turns per specialist agent
    if (lower.contains('budget_auditor_agent') ||
        lower.contains('financial audit') ||
        lower.contains('auditoría financiera') ||
        lower.contains('calculate_budget_math')) {
      final subtotal =
          (days * lodgingPerNight) + (days * foodPerDay) + activitiesTotal;
      final contingency = subtotal * 0.10;
      final grandTotal = subtotal + contingency;
      if (isSpanish) {
        final status = grandTotal <= userBudget
            ? 'DENTRO DEL PRESUPUESTO (WITHIN BUDGET)'
            : 'SOBRE PRESUPUESTO (OVER BUDGET)';
        return '''
- **Destino Auditado**: $destination ($days días, moneda objetivo `$currency`)
- **Hospedaje**: \$${lodgingPerNight.toStringAsFixed(0)}/noche × $days noches = \$${(days * lodgingPerNight).toStringAsFixed(2)} USD
- **Alimentación**: \$${foodPerDay.toStringAsFixed(0)}/día × $days días = \$${(days * foodPerDay).toStringAsFixed(2)} USD
- **Actividades y Transporte**: \$${activitiesTotal.toStringAsFixed(2)} USD
- **Reserva de Contingencia (10%)**: \$${contingency.toStringAsFixed(2)} USD
- **Gran Total Auditado**: **\$${grandTotal.toStringAsFixed(2)} USD** vs. Presupuesto **\$${userBudget.toStringAsFixed(2)} USD** (**$status**)''';
      }
      final status = grandTotal <= userBudget ? 'WITHIN BUDGET' : 'OVER BUDGET';
      return '''
- **Destination Audited**: $destination ($days days, target currency `$currency`)
- **Lodging**: \$${lodgingPerNight.toStringAsFixed(0)}/night × $days nights = \$${(days * lodgingPerNight).toStringAsFixed(2)} USD
- **Dining & Street Food**: \$${foodPerDay.toStringAsFixed(0)}/day × $days days = \$${(days * foodPerDay).toStringAsFixed(2)} USD
- **Activities & Transit**: \$${activitiesTotal.toStringAsFixed(2)} USD
- **10% Contingency Reserve**: \$${contingency.toStringAsFixed(2)} USD
- **Audited Grand Total**: **\$${grandTotal.toStringAsFixed(2)} USD** vs. Target Budget **\$${userBudget.toStringAsFixed(2)} USD** (**$status**)''';
    }

    if (lower.contains('concierge_agent') ||
        lower.contains('final brief') ||
        lower.contains('guía ejecutiva del concierge') ||
        lower.contains('save_trip_plan')) {
      return OnDeviceLiteRtGemmaLlm.buildRichConciergeGuideFallback(
        destination: destination,
        days: days,
        currency: currency,
        isSpanish: isSpanish,
      );
    }

    // Default: ScoutAgent rich Day-by-Day destination & route plan
    return OnDeviceLiteRtGemmaLlm.buildRichScoutDayByDayFallback(
      destination: destination,
      days: days,
      isSpanish: isSpanish,
    );
  }

  @override
  Future<void> dispose() async {
    _isInitialized = false;
  }

  static String _inferDestination(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('kyoto') || lower.contains('kioto')) {
      return 'Kyoto, Japan';
    }
    if (lower.contains('cartagena')) return 'Cartagena, Colombia';
    if (lower.contains('lisbon') || lower.contains('lisboa')) {
      return 'Lisbon, Portugal';
    }
    if (lower.contains('reykjavik') || lower.contains('reikiavik')) {
      return 'Reykjavik, Iceland';
    }
    if (lower.contains('tokyo') || lower.contains('tokio')) {
      return 'Tokyo, Japan';
    }
    if (lower.contains('paris') || lower.contains('parís')) {
      return 'Paris, France';
    }
    if (lower.contains('mexico city') ||
        lower.contains('cdmx') ||
        lower.contains('ciudad de méxico') ||
        lower.contains('ciudad de mexico')) {
      return 'Mexico City, Mexico';
    }
    if (lower.contains('london') || lower.contains('londres')) {
      return 'London, United Kingdom';
    }
    return 'Kyoto, Japan';
  }

  static int _inferDays(String text) {
    final match = RegExp(
      r'(\d+)\s*(?:-|\s)?\s*(?:d[ií]as?|days?|noches?|nights?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final parsed = int.tryParse(match.group(1)!);
      if (parsed != null && parsed >= 1 && parsed <= 30) {
        return parsed;
      }
    }
    return 4;
  }

  static String _inferCurrency(String text, String destination) {
    final upper = text.toUpperCase();
    for (final code in <String>[
      'JPY',
      'COP',
      'EUR',
      'GBP',
      'MXN',
      'CAD',
      'AUD',
      'CHF',
    ]) {
      if (RegExp('\\b$code\\b').hasMatch(upper)) {
        return code;
      }
    }
    if (destination.contains('Japan')) return 'JPY';
    if (destination.contains('Colombia')) return 'COP';
    if (destination.contains('Portugal') ||
        destination.contains('France') ||
        destination.contains('Iceland')) {
      return 'EUR';
    }
    if (destination.contains('United Kingdom')) return 'GBP';
    if (destination.contains('Mexico')) return 'MXN';
    return 'USD';
  }

  static double _inferUserBudget(String text, int days) {
    final budgetMatch = RegExp(
      r'\$\s*([\d,]+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (budgetMatch != null) {
      final cleaned = budgetMatch.group(1)!.replaceAll(',', '');
      final parsed = double.tryParse(cleaned);
      if (parsed != null && parsed >= 150) {
        return parsed;
      }
    }
    return (days * 300).toDouble();
  }

  static double _inferLodging(String destination) {
    if (destination.contains('Cartagena')) return 110.0;
    if (destination.contains('Kyoto')) return 145.0;
    if (destination.contains('Lisbon')) return 135.0;
    if (destination.contains('Reykjavik')) return 210.0;
    return 130.0;
  }

  static double _inferFood(String destination) {
    if (destination.contains('Cartagena')) return 45.0;
    if (destination.contains('Kyoto')) return 55.0;
    if (destination.contains('Lisbon')) return 50.0;
    if (destination.contains('Reykjavik')) return 75.0;
    return 50.0;
  }

  static double _inferActivities(String destination, int days) {
    if (destination.contains('Cartagena')) return 120.0;
    if (destination.contains('Kyoto')) return 160.0;
    if (destination.contains('Lisbon')) return 150.0;
    if (destination.contains('Reykjavik')) return 260.0;
    return (days * 40).toDouble();
  }
}
