import 'dart:async';
import 'dart:convert';

import 'package:adk_dart/adk_core.dart';

import '../../domain/use_cases/evaluate_trip_intake_use_case.dart';
import 'litert_chat_driver.dart';

export '../../domain/use_cases/evaluate_trip_intake_use_case.dart'
    show EvaluateTripIntakeUseCase, TripIntakeReadiness;

/// Custom `BaseLlm` adapter that bridges `flutter_adk` (`package:adk_dart/adk_core.dart`)
/// directly to the shared on-device `LiteRtChatDriver` (`gemma-4-E2B-it.litertlm`).
///
/// Supports:
/// 1. **Conversational Multi-Turn Intake (`coordinator_agent`)**: Greets the user
///    in their language (Spanish or English), asks for missing trip details
///    (Destination, Duration, Budget), and emits `transfer_to_agent` to
///    `pocket_squad_pipeline` once all 3 parameters are present.
/// 2. **Structured `<tool_call>` emission** with a 100% deterministic fallback
///    parameter extractor (`extractBudgetArgsFromRequest` / `extractSaveTripArgsFromRequest`)
///    so `Part.fromFunctionCall` always succeeds with accurate numbers on a 2B model.
/// 3. **Section-prefixed narrative responses** for `coordinator_agent`,
///    `scout_agent` (rich Day-by-Day itinerary with Morning/Afternoon/Evening places),
///    `budget_auditor_agent` (bulleted financial audit), and `concierge_agent`
///    (local gastronomy, insider logistics, and packing checklist).
class OnDeviceLiteRtGemmaLlm extends BaseLlm {
  OnDeviceLiteRtGemmaLlm({
    required this.driver,
    super.model = 'gemma-4-E2B-it.litertlm',
    this.onTurnEvent,
  });

  final LiteRtChatDriver driver;
  final void Function(String agentHint, String stage)? onTurnEvent;

  static const String calculateBudgetToolName = 'calculate_budget_math';
  static const String saveTripPlanToolName = 'save_trip_plan';
  static const String transferToAgentToolName = 'transfer_to_agent';
  static const String pipelineAgentTargetName = 'pocket_squad_pipeline';

  static const String coordinatorHeader =
      '\n\n### 🎯 CoordinatorAgent — Travel Intake\n';
  static const String scoutHeader =
      '\n\n### 🧭 ScoutAgent — Destination & Route\n';
  static const String budgetHeader =
      '\n\n### 💰 BudgetAuditorAgent — Financial Audit\n';
  static const String conciergeHeader =
      '\n\n### ✨ ConciergeAgent — Final Brief & Vault\n';

  static final RegExp _toolCallBlockPattern = RegExp(
    r'<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>',
    caseSensitive: false,
  );
  static final RegExp _jsonObjectPattern = RegExp(r'\{[\s\S]*\}');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final activeTool = _detectActiveToolName(request);
    final agentHint = _inferAgentHint(request, activeTool);

    // Case 0: Root Conversational CoordinatorAgent (`coordinator_agent`)
    if (agentHint == 'coordinator_agent') {
      final readiness = evaluateIntakeReadiness(request);
      if (!readiness.isComplete) {
        onTurnEvent?.call('coordinator_agent', 'conversational_intake');
        final intakePrompt = _buildCoordinatorIntakePrompt(
          request: request,
          readiness: readiness,
        );
        final systemInstruction = _buildCoordinatorSystemInstruction(readiness);

        String reply;
        try {
          reply = await driver.generateCompletion(
            prompt: intakePrompt,
            systemInstruction: systemInstruction,
            maxOutputTokens: 220,
          );
        } catch (_) {
          reply = _buildFallbackCoordinatorIntake(readiness);
        }
        if (reply.trim().isEmpty) {
          reply = _buildFallbackCoordinatorIntake(readiness);
        }

        final formatted = _prefixWithAgentHeader(
          text: reply.trim(),
          agentHint: 'coordinator_agent',
        );
        onTurnEvent?.call('coordinator_agent', 'completed');

        yield LlmResponse(
          modelVersion: model,
          partial: false,
          turnComplete: true,
          finishReason: 'STOP',
          content: Content(role: 'model', parts: <Part>[Part.text(formatted)]),
        );
        return;
      }

      if (!_hasFunctionResponseInCurrentTurn(
        request,
        transferToAgentToolName,
      )) {
        onTurnEvent?.call(
          'coordinator_agent',
          'tool_call:$transferToAgentToolName',
        );
        yield LlmResponse(
          modelVersion: model,
          partial: false,
          turnComplete: true,
          finishReason: 'STOP',
          content: Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: transferToAgentToolName,
                args: <String, dynamic>{'agent_name': pipelineAgentTargetName},
                id: 'call_${transferToAgentToolName}_${DateTime.now().microsecondsSinceEpoch}',
              ),
            ],
          ),
        );
        return;
      }

      final handoffText = readiness.isSpanish
          ? '¡Excelente! Ya tengo tu destino (**${readiness.detectedDestination}**), duración (**${readiness.detectedDays} días**) y presupuesto (**\$${readiness.detectedBudget?.toStringAsFixed(0)} USD**). Transfiriendo al equipo de especialistas...'
          : 'Excellent! I have your destination (**${readiness.detectedDestination}**), duration (**${readiness.detectedDays} days**), and budget (**\$${readiness.detectedBudget?.toStringAsFixed(0)} USD**). Transferring to the specialist squad...';
      final formattedHandoff = _prefixWithAgentHeader(
        text: handoffText,
        agentHint: 'coordinator_agent',
      );
      onTurnEvent?.call('coordinator_agent', 'completed');
      yield LlmResponse(
        modelVersion: model,
        partial: false,
        turnComplete: true,
        finishReason: 'STOP',
        content: Content(
          role: 'model',
          parts: <Part>[Part.text(formattedHandoff)],
        ),
      );
      return;
    }

    // Case 1: Specialist Tool Call Required (`calculate_budget_math` or `save_trip_plan`)
    if (activeTool != null &&
        !_hasFunctionResponseInCurrentTurn(request, activeTool)) {
      onTurnEvent?.call(agentHint, 'tool_call:$activeTool');

      final fallbackArgs = activeTool == calculateBudgetToolName
          ? extractBudgetArgsFromRequest(request)
          : extractSaveTripArgsFromRequest(request);

      final toolPrompt = _buildToolCallPrompt(
        request: request,
        toolName: activeTool,
        fallbackArgs: fallbackArgs,
      );

      String rawCompletion = '';
      try {
        rawCompletion = await driver.generateCompletion(
          prompt: toolPrompt,
          systemInstruction:
              'You are $agentHint. Output ONLY a single <tool_call>{"name":"$activeTool","args":{...}}</tool_call> JSON block.',
          maxOutputTokens: 220,
        );
      } catch (_) {
        rawCompletion = '';
      }

      final parsedArgs = _parseToolArgsFromCompletion(
        rawCompletion,
        expectedToolName: activeTool,
      );
      final finalArgs = _mergeToolArgs(
        fallbackArgs: fallbackArgs,
        modelArgs: parsedArgs,
        toolName: activeTool,
      );

      yield LlmResponse(
        modelVersion: model,
        partial: false,
        turnComplete: true,
        finishReason: 'STOP',
        content: Content(
          role: 'model',
          parts: <Part>[
            Part.fromFunctionCall(
              name: activeTool,
              args: finalArgs,
              id: 'call_${activeTool}_${DateTime.now().microsecondsSinceEpoch}',
            ),
          ],
        ),
      );
      return;
    }

    // Case 2: Specialist Agent Narrative Response
    onTurnEvent?.call(agentHint, 'generating_narrative');

    final narrativePrompt = _buildNarrativePrompt(
      request: request,
      agentHint: agentHint,
    );
    final systemInstruction = _buildConciseSystemInstruction(
      request: request,
      agentHint: agentHint,
    );
    final maxOutputTokens = agentHint == 'scout_agent' ? 550 : 340;

    String narrative;
    try {
      narrative = await driver.generateCompletion(
        prompt: narrativePrompt,
        systemInstruction: systemInstruction,
        maxOutputTokens: maxOutputTokens,
      );
    } catch (error) {
      narrative = _buildFallbackNarrative(
        request: request,
        agentHint: agentHint,
        error: error,
      );
    }

    if (narrative.trim().isEmpty) {
      narrative = _buildFallbackNarrative(
        request: request,
        agentHint: agentHint,
      );
    } else if (agentHint == 'scout_agent') {
      final readiness = evaluateIntakeReadiness(request);
      final budgetArgs = extractBudgetArgsFromRequest(request);
      final days =
          readiness.detectedDays ?? (budgetArgs['days'] as num?)?.toInt() ?? 3;
      final userPrompt = _extractLatestUserMissionPrompt(request);
      final destination = extractDestinationFromText(
        userPrompt.isNotEmpty
            ? userPrompt
            : (readiness.detectedDestination ?? ''),
      );
      if (!_hasValidDayByDayItinerary(narrative, days)) {
        narrative = buildRichScoutDayByDayFallback(
          destination: destination,
          days: days,
          isSpanish: readiness.isSpanish,
        );
      }
    }

    final formatted = _prefixWithAgentHeader(
      text: narrative.trim(),
      agentHint: agentHint,
    );

    onTurnEvent?.call(agentHint, 'completed');

    yield LlmResponse(
      modelVersion: model,
      partial: false,
      turnComplete: true,
      finishReason: 'STOP',
      content: Content(role: 'model', parts: <Part>[Part.text(formatted)]),
    );
  }

  /// Collects all real user messages from [request] belonging to the active
  /// trip intake conversation. Resets automatically if a new user message
  /// arrives after a completed `concierge_agent` pipeline run.
  static List<String> extractActiveIntakeUserMessages(LlmRequest request) {
    final userMessages = <String>[];
    var pipelineCompletedSinceLastReset = false;

    for (final content in request.contents) {
      final text = content.parts
          .where((p) => p.text != null && p.text!.trim().isNotEmpty)
          .map((p) => p.text!.trim())
          .join(' ')
          .trim();

      if (text.contains('[concierge_agent] said:') ||
          text.contains('### ✨ ConciergeAgent') ||
          text.contains('### 🛎️ ConciergeAgent')) {
        pipelineCompletedSinceLastReset = true;
      }

      if (content.role != 'user') continue;
      final hasFunctionResponse = content.parts.any(
        (p) => p.functionResponse != null,
      );
      if (hasFunctionResponse) continue;
      if (text.isEmpty) continue;
      if (_isSyntheticAdkContextText(text)) continue;

      if (pipelineCompletedSinceLastReset) {
        userMessages.clear();
        pipelineCompletedSinceLastReset = false;
      }
      userMessages.add(text);
    }

    return userMessages;
  }

  /// Evaluates multi-turn intake readiness across all active user messages in [request].
  static TripIntakeReadiness evaluateIntakeReadiness(LlmRequest request) {
    final messages = extractActiveIntakeUserMessages(request);
    return evaluateIntakeText(messages.join(' | '));
  }

  /// Evaluates whether [aggregatedText] contains an explicit Destination,
  /// Duration (days), and Budget by delegating to [EvaluateTripIntakeUseCase].
  static TripIntakeReadiness evaluateIntakeText(String aggregatedText) {
    return EvaluateTripIntakeUseCase.evaluateText(aggregatedText);
  }

  /// Extracts deterministic budget arguments (`days`, `lodging_per_night_usd`,
  /// `food_per_day_usd`, `activities_total_usd`, `target_currency`,
  /// `user_budget_usd`) from [request].
  static Map<String, dynamic> extractBudgetArgsFromRequest(LlmRequest request) {
    final userPrompt = _extractLatestUserMissionPrompt(request);
    final fullContext = _flattenRequestText(request);
    final combined = '$userPrompt\n$fullContext';

    final destination = extractDestinationFromText(
      userPrompt.isNotEmpty ? userPrompt : fullContext,
    );
    final days = _extractDays(userPrompt) ?? _extractDays(fullContext) ?? 4;
    final currency =
        _extractCurrency(userPrompt) ??
        _extractCurrency(fullContext) ??
        _defaultCurrencyForDestination(destination);
    final userBudget =
        _extractUserBudgetUsd(userPrompt) ??
        _extractUserBudgetUsd(fullContext) ??
        (days * 300.0);

    final lodgingPerNight =
        _extractLabeledNumber(
          combined,
          patterns: <RegExp>[
            RegExp(
              r'lodging_per_night_usd[`"\s:=]*\$?\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
            RegExp(
              r'lodging[^.\n\d]{0,25}\$\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
            RegExp(
              r'\$\s*(\d+(?:\.\d+)?)\s*(?:/|\s*per\s*)\s*night',
              caseSensitive: false,
            ),
          ],
        ) ??
        _defaultLodgingPerNight(destination);

    final foodPerDay =
        _extractLabeledNumber(
          combined,
          patterns: <RegExp>[
            RegExp(
              r'food_per_day_usd[`"\s:=]*\$?\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
            RegExp(
              r'(?:food|dining)[^.\n\d]{0,25}\$\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
            RegExp(
              r'\$\s*(\d+(?:\.\d+)?)\s*(?:/|\s*per\s*)\s*day',
              caseSensitive: false,
            ),
          ],
        ) ??
        _defaultFoodPerDay(destination);

    final activitiesTotal =
        _extractLabeledNumber(
          combined,
          patterns: <RegExp>[
            RegExp(
              r'activities_total_usd[`"\s:=]*\$?\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
            RegExp(
              r'activities[^.\n\d]{0,25}\$\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ),
          ],
        ) ??
        _defaultActivitiesTotal(destination, days);

    return <String, dynamic>{
      'days': days,
      'lodging_per_night_usd': lodgingPerNight,
      'food_per_day_usd': foodPerDay,
      'activities_total_usd': activitiesTotal,
      'target_currency': currency,
      'user_budget_usd': userBudget,
    };
  }

  /// Extracts deterministic `save_trip_plan` arguments from [request],
  /// combining destination metadata, Day-by-Day itinerary summary, checklist
  /// items, and budget parameters.
  static Map<String, dynamic> extractSaveTripArgsFromRequest(
    LlmRequest request,
  ) {
    final readiness = evaluateIntakeReadiness(request);
    final isSpanish = readiness.isSpanish;
    final budgetArgs = extractBudgetArgsFromRequest(request);
    final userPrompt = _extractLatestUserMissionPrompt(request);
    final fullContext = _flattenRequestText(request);
    final destination = extractDestinationFromText(
      userPrompt.isNotEmpty ? userPrompt : fullContext,
    );
    final days = (budgetArgs['days'] as num?)?.toInt() ?? 4;
    final dayByDaySummary = buildRichScoutDayByDayFallback(
      destination: destination,
      days: days,
      isSpanish: isSpanish,
    );

    return <String, dynamic>{
      'destination': destination,
      'days': days,
      'itinerary_summary': dayByDaySummary,
      'packing_checklist': isSpanish
          ? <String>[
              'Pasaporte/documento y copias digitales de reservas',
              'Calzado cómodo para caminatas por barrios históricos',
              'Bloqueador solar, gafas de sol y ropa fresca/transpirable',
              'Batería portátil (power bank) y adaptador universal',
            ]
          : <String>[
              'Passport & digital copies of reservations',
              'Universal travel adapter & portable charger',
              'Comfortable walking shoes for daily neighborhood routes',
              'Weather-appropriate outer layer & local transit card',
            ],
      'concierge_notes': isSpanish
          ? 'Visita los sitios emblemáticos antes de las 8:30 AM y reserva restaurantes locales con 3-5 días de anticipación.'
          : 'Book signature cultural entries and popular local dining 1-2 weeks prior to departure.',
      ...budgetArgs,
    };
  }

  /// Extracts a human-readable destination label from prompt text.
  static String extractDestinationFromText(String text) {
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
    if (lower.contains('osaka')) return 'Osaka, Japan';
    if (lower.contains('paris') || lower.contains('parís')) {
      return 'Paris, France';
    }
    if (lower.contains('rome') || lower.contains('roma')) return 'Rome, Italy';
    if (lower.contains('barcelona')) return 'Barcelona, Spain';
    if (lower.contains('madrid')) return 'Madrid, Spain';
    if (lower.contains('london') || lower.contains('londres')) {
      return 'London, United Kingdom';
    }
    if (lower.contains('mexico city') ||
        lower.contains('cdmx') ||
        lower.contains('ciudad de méxico') ||
        lower.contains('ciudad de mexico')) {
      return 'Mexico City, Mexico';
    }
    if (lower.contains('cancun') || lower.contains('cancún')) {
      return 'Cancún, Mexico';
    }
    if (lower.contains('medellin') || lower.contains('medellín')) {
      return 'Medellín, Colombia';
    }
    if (lower.contains('bogota') || lower.contains('bogotá')) {
      return 'Bogotá, Colombia';
    }

    final explicit = EvaluateTripIntakeUseCase.detectExplicitDestination(text);
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }

    return 'Kyoto, Japan';
  }

  /// Builds a complete, place-rich Day 1..N itinerary in Spanish or English
  /// with Morning / Afternoon / Evening activities and real named landmarks.
  static String buildRichScoutDayByDayFallback({
    required String destination,
    required int days,
    required bool isSpanish,
  }) {
    final clampedDays = days.clamp(1, 14);
    final lowerDest = destination.toLowerCase();

    final dayPlans = _resolveDestinationDayPlans(
      lowerDestination: lowerDest,
      destinationLabel: destination,
      days: clampedDays,
      isSpanish: isSpanish,
    );

    final buffer = StringBuffer();
    for (var i = 0; i < clampedDays; i++) {
      final plan = dayPlans[i % dayPlans.length];
      final dayNumber = i + 1;
      if (i > 0) buffer.writeln('\n');
      if (isSpanish) {
        buffer.writeln('### Día $dayNumber: ${plan.title}');
        buffer.writeln('- **Mañana**: ${plan.morning}');
        buffer.writeln('- **Tarde**: ${plan.afternoon}');
        buffer.write('- **Noche**: ${plan.evening}');
      } else {
        buffer.writeln('### Day $dayNumber: ${plan.title}');
        buffer.writeln('- **Morning**: ${plan.morning}');
        buffer.writeln('- **Afternoon**: ${plan.afternoon}');
        buffer.write('- **Evening**: ${plan.evening}');
      }
    }
    return buffer.toString();
  }

  static List<_DayRoutePlan> _resolveDestinationDayPlans({
    required String lowerDestination,
    required String destinationLabel,
    required int days,
    required bool isSpanish,
  }) {
    if (lowerDestination.contains('cartagena')) {
      if (isSpanish) {
        return const <_DayRoutePlan>[
          _DayRoutePlan(
            title: 'Centro Histórico y Ciudad Amurallada',
            morning: 'Entrada por la **Torre del Reloj**, recorrido por la **Plaza de los Coches**, el **Portal de los Dulces** y visita a la **Catedral de Santa Catalina de Alejandría** y el **Palacio de la Inquisición**.',
            afternoon: 'Almuerzo típico caribeño cerca de la **Plaza de San Diego** y caminata por las calles coloniales de **Las Bóvedas** y el barrio **San Diego**.',
            evening: 'Atardecer frente al mar Caribe desde el **Baluarte de Santo Domingo** y cena al aire libre en la **Plaza Santo Domingo**.',
          ),
          _DayRoutePlan(
            title: 'Castillo de San Felipe y Barrio Getsemaní',
            morning: 'Visita temprana (8:00 AM) al imponente **Castillo de San Felipe de Barajas** para explorar sus túneles y miradores, seguido del **Convento de la Popa**.',
            afternoon: 'Almuerzo local en **Getsemaní** y recorrido a pie por el **Callejón Ancho**, la **Calle de las Sombrillas** y los murales de arte urbano en la **Calle de la Sierpe**.',
            evening: 'Ambiente bohemio, música en vivo y gastronomía callejera en la **Plaza de la Trinidad** en el corazón de **Getsemaní**.',
          ),
          _DayRoutePlan(
            title: 'Islas del Rosario y Bahía de Cartagena',
            morning: 'Salida en lancha desde el **Muelle de la Bodeguita** hacia el **Parque Nacional Natural Corales del Rosario** (**Isla Grande** o **Playa Blanca** en Barú) para nadar en aguas cristalinas y hacer snorkel.',
            afternoon: 'Almuerzo isleño de **pargo rojo frito con arroz con coco y patacones** frente al mar y tarde de descanso en la playa.',
            evening: 'Regreso al **Muelle de los Pegasos**, caminata nocturna por la **Bahía de las Ánimas** y cena de mariscos en el **Centro Histórico**.',
          ),
          _DayRoutePlan(
            title: 'Bocagrande, Manga y Sabores Costeños',
            morning: 'Caminata matutina por el **Paseo Peatonal de Bocagrande** y visita al **Museo del Oro Zenú** en la **Plaza de Bolívar**.',
            afternoon: 'Recorrido arquitectónico por las mansiones republicanas de **Manga**, el **Fuerte del Pastelillo** y degustación de frutas tropicales.',
            evening: 'Cena de despedida con vista a la bahía en el **Muelle de Manga** o terraza colonial del **Centro Amurallado**.',
          ),
        ];
      }
      return const <_DayRoutePlan>[
        _DayRoutePlan(
          title: 'Historic Walled City & San Diego',
          morning: 'Enter through the iconic **Torre del Reloj**, stroll **Plaza de los Coches** and **Portal de los Dulces**, and visit **Santa Catalina de Alejandría Cathedral**.',
          afternoon: 'Enjoy a Caribbean seafood lunch in **Plaza de San Diego** and explore the artisan arches of **Las Bóvedas**.',
          evening: 'Catch the Caribbean sunset along the historic **Murallas (Baluarte de Santo Domingo)** followed by dinner at **Plaza Santo Domingo**.',
        ),
        _DayRoutePlan(
          title: 'Castillo de San Felipe & Getsemaní Street Art',
          morning: 'Arrive at 8:00 AM at **Castillo de San Felipe de Barajas** to tour the fortress tunnels and panoramic ramparts, then visit **Convento de la Popa**.',
          afternoon: 'Lunch in **Getsemaní** followed by a walking tour of **Callejón Ancho**, **Calle de las Sombrillas**, and vibrant street murals.',
          evening: 'Experience live street performers, local music, and open-air dining around **Plaza de la Trinidad** in **Getsemaní**.',
        ),
        _DayRoutePlan(
          title: 'Rosario Islands & Caribbean Coast',
          morning: 'Depart from **Muelle de la Bodeguita** by boat to **Islas del Rosario** (**Isla Grande**) for coral reef snorkeling and turquoise beaches.',
          afternoon: 'Beachfront lunch of fresh fried red snapper with coconut rice and plantains before returning across **Cartagena Bay**.',
          evening: 'Evening harbor stroll past **Muelle de los Pegasos** and farewell dinner in the **Walled City**.',
        ),
      ];
    }

    if (lowerDestination.contains('kyoto') ||
        lowerDestination.contains('kioto')) {
      if (isSpanish) {
        return const <_DayRoutePlan>[
          _DayRoutePlan(
            title: 'Fushimi Inari, Higashiyama y Gion',
            morning: 'Recorrido al amanecer por los miles de torii bermellón del santuario **Fushimi Inari-taisha** y visita al templo **Tofuku-ji**.',
            afternoon: 'Almuerzo en el **Mercado Nishiki** y ascenso al templo **Kiyomizu-dera** caminando por las calles históricas **Sannenzaka** y **Ninenzaka**.',
            evening: 'Paseo al anochecer por **Hanamikoji-dori** en el barrio de geishas de **Gion** y cena junto al río en **Pontocho Alley**.',
          ),
          _DayRoutePlan(
            title: 'Bosque de Bambú de Arashiyama y Kinkaku-ji',
            morning: 'Caminata temprana por el **Bosque de Bambú de Arashiyama**, jardines zen del templo **Tenryu-ji** y vistas desde el puente **Togetsukyo**.',
            afternoon: 'Almuerzo tradicional de tofu kyotoense y visita al **Pabellón Dorado (Kinkaku-ji)** y al jardín seco de rocas de **Ryoan-ji**.',
            evening: 'Cena de ramen y izakaya en el distrito de **Kiyamachi** y paseo nocturno por la ribera del **río Kamogawa**.',
          ),
          _DayRoutePlan(
            title: 'Camino del Filósofo, Castillo Nijo y Uji',
            morning: 'Recorrido por el **Camino del Filósofo** desde el **Pabellón de Plata (Ginkaku-ji)** hasta el complejo zen de **Nanzen-ji**.',
            afternoon: 'Visita a los pisos de ruiseñor del **Castillo Nijo-jo** y tarde en **Uji** para conocer el templo **Byodoin** y degustar té matcha auténtico.',
            evening: 'Vistas panorámicas desde **Kyoto Station Skyway** y cena de obanzai tradicional en el centro de Kioto.',
          ),
          _DayRoutePlan(
            title: 'Palacio Imperial y Excursión Cultural a Nara',
            morning: 'Paseo por los jardines del **Palacio Imperial de Kioto (Kyoto Gosho)** y el santuario **Shimogamo-jinja**.',
            afternoon: 'Excursión en tren a **Nara** para visitar el **Parque de Nara**, el Gran Buda del templo **Todai-ji** y los faroles de **Kasuga Taisha**.',
            evening: 'Cena de despedida en el callejón gastronómico de **Pontocho** o zona de **Sanjo**.',
          ),
        ];
      }
      return const <_DayRoutePlan>[
        _DayRoutePlan(
          title: 'Fushimi Inari, Historic Higashiyama & Gion',
          morning: 'Early morning walk through the vermilion torii gates of **Fushimi Inari-taisha** before crowds arrive.',
          afternoon: 'Graze through **Nishiki Market** for lunch, then visit **Kiyomizu-dera** and stroll the preserved lanes of **Sannenzaka** and **Ninenzaka**.',
          evening: 'Lantern-lit walk along **Hanamikoji-dori** in **Gion** and riverside dining in **Pontocho Alley**.',
        ),
        _DayRoutePlan(
          title: 'Arashiyama Bamboo Grove & Golden Pavilion',
          morning: 'Explore the **Arashiyama Bamboo Grove**, **Tenryu-ji Temple** gardens, and **Togetsukyo Bridge**.',
          afternoon: 'Visit the iconic **Kinkaku-ji (Golden Pavilion)** and the zen rock garden at **Ryoan-ji**.',
          evening: 'Craft ramen and izakaya tasting along **Kiyamachi Street** and the **Kamogawa River**.',
        ),
        _DayRoutePlan(
          title: 'Philosopher’s Path, Nijo Castle & Uji Matcha',
          morning: 'Walk the **Philosopher’s Path** from **Ginkaku-ji (Silver Pavilion)** down to **Nanzen-ji**.',
          afternoon: 'Tour **Nijo-jo Castle** and take a short train to **Uji** for **Byodoin Temple** and ceremonial matcha.',
          evening: 'Panoramic city views from **Kyoto Station Skyway** and traditional obanzai dinner.',
        ),
        _DayRoutePlan(
          title: 'Kyoto Imperial Park & Nara Sanctuary Excursion',
          morning: 'Morning stroll through **Kyoto Imperial Palace Park** and **Shimogamo Shrine**.',
          afternoon: 'Afternoon excursion to **Nara Park**, **Todai-ji Great Buddha**, and **Kasuga Taisha**.',
          evening: 'Farewell kaiseki or yakitori dinner in **Sanjo** and **Pontocho**.',
        ),
      ];
    }

    if (lowerDestination.contains('tokyo') ||
        lowerDestination.contains('tokio')) {
      if (isSpanish) {
        return const <_DayRoutePlan>[
          _DayRoutePlan(
            title: 'Asakusa Tradicional, Parque Ueno y Akihabara',
            morning: 'Visita temprana al templo **Senso-ji**, puerta **Kaminarimon** y compras tradicionales en la calle **Nakamise-dori** en **Asakusa**.',
            afternoon: 'Almuerzo callejero en el mercado **Ameyoko** y recorrido por el **Parque Ueno** y sus museos.',
            evening: 'Tarde-noche en las tiendas de electrónica y anime de **Akihabara** y vistas desde **Tokyo Skytree**.',
          ),
          _DayRoutePlan(
            title: 'Harajuku, Santuario Meiji y Shibuya',
            morning: 'Bosque sagrado del **Santuario Meiji Jingu**, calle **Takeshita** en **Harajuku** y arquitectura de **Omotesando**.',
            afternoon: 'Almuerzo de sushi o tonkatsu en **Shibuya**, cruce peatonal de **Shibuya Crossing** y estatua de **Hachiko**.',
            evening: 'Atardecer en el mirador **Shibuya Sky** y cena en los callejones de **Nonbei Yokocho**.',
          ),
          _DayRoutePlan(
            title: 'Mercado de Tsukiji, Ginza y Shinjuku',
            morning: 'Desayuno de mariscos frescos y tamagoyaki en el **Mercado Exterior de Tsukiji** y paseo por los jardines **Hamarikyu**.',
            afternoon: 'Recorrido por las galerías y tiendas insignia de **Ginza** y el **Palacio Imperial (Jardines del Este)**.',
            evening: 'Mirador gratuito del **Gobierno Metropolitano de Tokio** en **Shinjuku** y cena en **Omoide Yokocho**.',
          ),
        ];
      }
    }

    if (isSpanish) {
      return <_DayRoutePlan>[
        _DayRoutePlan(
          title:
              'Centro Histórico y Monumentos Emblemáticos de $destinationLabel',
          morning:
              'Recorrido a pie temprano por la **Plaza Principal**, la **Catedral Histórica** y los monumentos patrimoniales del casco antiguo de **$destinationLabel**.',
          afternoon: 'Almuerzo de gastronomía típica en el **Mercado Central** y visita al **Museo Principal** y calles peatonales históricas.',
          evening: 'Atardecer desde el **Mirador Panorámico** de la ciudad y cena en la zona gastronómica tradicional.',
        ),
        _DayRoutePlan(
          title:
              'Barrios Culturales, Arte Urbano y Parques de $destinationLabel',
          morning:
              'Exploración de la fortaleza o parque emblemático de **$destinationLabel** en horario matutino para aprovechar el clima fresco y evitar filas.',
          afternoon: 'Almuerzo en bistró local y caminata por el **Barrio Bohemio y Cultural** con galerías, cafés de especialidad y artesanías.',
          evening: 'Paseo nocturno iluminado por la plaza bohemia y cena con música local en vivo.',
        ),
        _DayRoutePlan(
          title: 'Excursión Escénica, Costa o Naturaleza Cercana',
          morning:
              'Salida temprana hacia el **paseo costero, ribera o reserva natural** más representativa de **$destinationLabel**.',
          afternoon: 'Almuerzo tradicional frente al paisaje natural y tarde de actividades al aire libre y mercados de artesanos.',
          evening:
              'Cena de despedida degustando los platos insignia de **$destinationLabel** en el distrito histórico.',
        ),
      ];
    }

    return <_DayRoutePlan>[
      _DayRoutePlan(
        title: 'Historic Core & Iconic Landmarks of $destinationLabel',
        morning:
            'Early morning walking tour of the **Main Historic Plaza**, **Cathedral**, and heritage architecture in old-town **$destinationLabel**.',
        afternoon: 'Authentic local lunch at the **Central Market** followed by the **National Cultural Museum** and pedestrian artisan lanes.',
        evening: 'Sunset at the **Panoramic Viewpoint** and dinner in the historic culinary quarter.',
      ),
      _DayRoutePlan(
        title: 'Cultural Neighborhoods, Cafés & Local Markets',
        morning:
            'Morning visit to **$destinationLabel**’s signature fortress, botanical park, or sanctuary before peak hours.',
        afternoon: 'Lunch in the **Bohemian Arts District** and afternoon exploration of street murals, specialty coffee roasters, and galleries.',
        evening: 'Evening stroll through lively neighborhood squares with local live music and tapas/small plates.',
      ),
      _DayRoutePlan(
        title: 'Scenic Waterfront, Excursion & Farewell Dining',
        morning:
            'Half-day excursion to the scenic waterfront, coastal promenade, or nature lookout surrounding **$destinationLabel**.',
        afternoon: 'Relaxed regional lunch and craft shopping along the main promenade.',
        evening:
            'Farewell tasting dinner featuring **$destinationLabel**’s signature regional dishes.',
      ),
    ];
  }

  static bool _hasValidDayByDayItinerary(String text, int days) {
    final lower = text.toLowerCase();
    if (lower.contains('|---|') || lower.contains('| --- |')) {
      return false;
    }

    final hasDay1 = RegExp(
      r'(?:d[ií]a|day)\s*1\b',
      caseSensitive: false,
    ).hasMatch(lower);
    if (!hasDay1) return false;

    if (days >= 2) {
      final hasDay2 = RegExp(
        r'(?:d[ií]a|day)\s*2\b',
        caseSensitive: false,
      ).hasMatch(lower);
      if (!hasDay2) return false;
    }

    final requiredLastDay = days.clamp(1, 5);
    if (requiredLastDay >= 3) {
      final hasLastDay = RegExp(
        '(?:d[ií]a|day)\\s*$requiredLastDay\\b',
        caseSensitive: false,
      ).hasMatch(lower);
      if (!hasLastDay) return false;
    }

    final hasTimeOfDayMarkers = RegExp(
      r'\b(?:mañana|tarde|noche|morning|afternoon|evening)\b',
      caseSensitive: false,
    ).hasMatch(lower);
    return hasTimeOfDayMarkers;
  }

  String? _detectActiveToolName(LlmRequest request) {
    if (request.toolsDict.containsKey(calculateBudgetToolName)) {
      return calculateBudgetToolName;
    }
    if (request.toolsDict.containsKey(saveTripPlanToolName)) {
      return saveTripPlanToolName;
    }

    final declarations = request.config.tools;
    if (declarations != null) {
      for (final tool in declarations) {
        for (final fn in tool.functionDeclarations) {
          if (fn.name == calculateBudgetToolName) {
            return calculateBudgetToolName;
          }
          if (fn.name == saveTripPlanToolName) {
            return saveTripPlanToolName;
          }
        }
      }
    }
    return null;
  }

  String _inferAgentHint(LlmRequest request, String? activeTool) {
    if (activeTool == calculateBudgetToolName) {
      return 'budget_auditor_agent';
    }
    if (activeTool == saveTripPlanToolName) {
      return 'concierge_agent';
    }
    if (request.toolsDict.containsKey(transferToAgentToolName)) {
      return 'coordinator_agent';
    }

    final sys = (request.config.systemInstruction ?? '').toLowerCase();
    if (sys.contains('you are `coordinator_agent`') ||
        sys.contains('you are coordinator_agent')) {
      return 'coordinator_agent';
    }
    if (sys.contains('you are `budget_auditor_agent`') ||
        sys.contains('you are budget_auditor_agent')) {
      return 'budget_auditor_agent';
    }
    if (sys.contains('you are `concierge_agent`') ||
        sys.contains('you are concierge_agent')) {
      return 'concierge_agent';
    }
    if (sys.contains('you are `scout_agent`') ||
        sys.contains('you are scout_agent')) {
      return 'scout_agent';
    }
    if (sys.contains('coordinator_agent')) {
      return 'coordinator_agent';
    }
    if (sys.contains('budget_auditor_agent') ||
        sys.contains('budget auditor')) {
      return 'budget_auditor_agent';
    }
    if (sys.contains('concierge_agent') ||
        sys.contains('chief travel concierge')) {
      return 'concierge_agent';
    }
    return 'scout_agent';
  }

  static bool _isSyntheticAdkContextText(String text) {
    return text.startsWith('For context:') ||
        text.startsWith('[coordinator_agent]') ||
        text.startsWith('[scout_agent]') ||
        text.startsWith('[budget_auditor_agent]') ||
        text.startsWith('[concierge_agent]') ||
        text.startsWith('Handle the requests as specified') ||
        text.startsWith('Continue processing previous requests');
  }

  bool _hasFunctionResponseInCurrentTurn(LlmRequest request, String toolName) {
    for (var i = request.contents.length - 1; i >= 0; i--) {
      final content = request.contents[i];
      for (final part in content.parts) {
        if (part.functionResponse?.name == toolName) {
          return true;
        }
      }

      // Stop scanning backwards once we reach the user's originating prompt
      // (ignoring ADK's synthesized "For context:" other-agent wrapper messages).
      final isUserRole = content.role == 'user';
      final hasFunctionResponse = content.parts.any(
        (p) => p.functionResponse != null,
      );
      if (isUserRole && !hasFunctionResponse) {
        final joinedText = content.parts
            .map((p) => p.text ?? '')
            .join(' ')
            .trim();
        if (joinedText.isNotEmpty && !_isSyntheticAdkContextText(joinedText)) {
          return false;
        }
      }
    }
    return false;
  }

  String _buildCoordinatorIntakePrompt({
    required LlmRequest request,
    required TripIntakeReadiness readiness,
  }) {
    final missingLabels = readiness.missingFields
        .map((field) {
          if (readiness.isSpanish) {
            return switch (field) {
              'destination' => 'Destino (ciudad o país)',
              'days' => 'Duración (número de días)',
              'budget' => 'Presupuesto total (ej. \$1,200 USD)',
              _ => field,
            };
          }
          return switch (field) {
            'destination' => 'Destination (city or country)',
            'days' => 'Duration (number of days)',
            'budget' => 'Total Budget (e.g. \$1,200 USD)',
            _ => field,
          };
        })
        .join(', ');

    final languageLabel = readiness.isSpanish ? 'Spanish' : 'English';
    return '''
Travel Intake Status (Language: $languageLabel):
- User conversation so far: ${readiness.aggregatedUserText}
- Detected destination: ${readiness.detectedDestination ?? 'MISSING'}
- Detected duration (days): ${readiness.detectedDays?.toString() ?? 'MISSING'}
- Detected budget: ${readiness.detectedBudget != null ? '\$${readiness.detectedBudget!.toStringAsFixed(0)}' : 'MISSING'}
- Missing fields required before launching the specialist squad: $missingLabels

Reply warmly in $languageLabel as `coordinator_agent`. Acknowledge any details already provided and ask clearly for the missing fields ($missingLabels). Keep it concise (2-4 sentences).''';
  }

  String _buildCoordinatorSystemInstruction(TripIntakeReadiness readiness) {
    if (readiness.isSpanish) {
      return 'You are coordinator_agent, the friendly Travel Concierge Coordinator of Pocket Squad. Respond in natural, warm Spanish. Ask only for the missing trip details (Destination, Duration in days, Total Budget) before activating the squad.';
    }
    return 'You are coordinator_agent, the friendly Travel Concierge Coordinator of Pocket Squad. Respond in natural, warm English. Ask only for the missing trip details (Destination, Duration in days, Total Budget) before activating the squad.';
  }

  String _buildFallbackCoordinatorIntake(TripIntakeReadiness readiness) {
    if (readiness.isSpanish) {
      final knownParts = <String>[];
      if (readiness.detectedDestination != null) {
        knownParts.add('destino **${readiness.detectedDestination}**');
      }
      if (readiness.detectedDays != null) {
        knownParts.add('**${readiness.detectedDays} días**');
      }
      if (readiness.detectedBudget != null) {
        knownParts.add(
          'presupuesto de **\$${readiness.detectedBudget!.toStringAsFixed(0)} USD**',
        );
      }

      final missingBullets = <String>[];
      if (!readiness.hasDestination) {
        missingBullets.add(
          '- **Destino**: ¿A qué ciudad o país te gustaría viajar?',
        );
      }
      if (!readiness.hasDays) {
        missingBullets.add(
          '- **Duración**: ¿Cuántos días o noches durará tu viaje?',
        );
      }
      if (!readiness.hasBudget) {
        missingBullets.add(
          '- **Presupuesto total**: ¿Cuál es tu presupuesto estimado (ej. `\$1,200 USD`)?',
        );
      }

      final intro = knownParts.isEmpty
          ? '¡Hola! Bienvenido a **Pocket Squad**. Soy tu **CoordinatorAgent**.'
          : '¡Excelente! Ya tomé nota de tu ${knownParts.join(' y ')}.';

      return '$intro\n'
          'Para activar al equipo de especialistas (**ScoutAgent** → **BudgetAuditorAgent** → **ConciergeAgent**), por favor indícame:\n'
          '${missingBullets.join('\n')}';
    }

    final knownParts = <String>[];
    if (readiness.detectedDestination != null) {
      knownParts.add('destination **${readiness.detectedDestination}**');
    }
    if (readiness.detectedDays != null) {
      knownParts.add('**${readiness.detectedDays} days**');
    }
    if (readiness.detectedBudget != null) {
      knownParts.add(
        'budget of **\$${readiness.detectedBudget!.toStringAsFixed(0)} USD**',
      );
    }

    final missingBullets = <String>[];
    if (!readiness.hasDestination) {
      missingBullets.add(
        '- **Destination**: Which city or country would you like to visit?',
      );
    }
    if (!readiness.hasDays) {
      missingBullets.add(
        '- **Duration**: How many days or nights are you planning?',
      );
    }
    if (!readiness.hasBudget) {
      missingBullets.add(
        '- **Total Budget**: What is your target budget (e.g., `\$1,200 USD`)?',
      );
    }

    final intro = knownParts.isEmpty
        ? 'Welcome to **Pocket Squad**! I am your **CoordinatorAgent**.'
        : 'Got it! I have noted your ${knownParts.join(' and ')}.';

    return '$intro\n'
        'Before I launch our 3-agent specialist pipeline (**ScoutAgent** → **BudgetAuditorAgent** → **ConciergeAgent**), please share:\n'
        '${missingBullets.join('\n')}';
  }

  String _buildToolCallPrompt({
    required LlmRequest request,
    required String toolName,
    required Map<String, dynamic> fallbackArgs,
  }) {
    final userPrompt = _extractLatestUserMissionPrompt(request);
    final exampleCall = jsonEncode(<String, dynamic>{
      'name': toolName,
      'args': fallbackArgs,
    });
    return '''
User travel mission: $userPrompt
You MUST call the tool `$toolName` now.
Respond with ONLY a valid <tool_call> block in this exact format:
<tool_call>$exampleCall</tool_call>''';
  }

  Map<String, dynamic>? _parseToolArgsFromCompletion(
    String rawCompletion, {
    required String expectedToolName,
  }) {
    if (rawCompletion.trim().isEmpty) return null;

    final tagMatch = _toolCallBlockPattern.firstMatch(rawCompletion);
    final candidateJson =
        tagMatch?.group(1) ??
        _jsonObjectPattern.firstMatch(rawCompletion)?.group(0);
    if (candidateJson == null) return null;

    try {
      final decoded = jsonDecode(candidateJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['args'] is Map) {
        return Map<String, dynamic>.from(map['args'] as Map);
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _mergeToolArgs({
    required Map<String, dynamic> fallbackArgs,
    required Map<String, dynamic>? modelArgs,
    required String toolName,
  }) {
    if (modelArgs == null || modelArgs.isEmpty) {
      return fallbackArgs;
    }

    final merged = Map<String, dynamic>.from(fallbackArgs);
    for (final entry in modelArgs.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      if (value is num && value <= 0) continue;
      merged[entry.key] = value;
    }

    // Always preserve explicit user prompt constraints (days, currency, budget, destination)
    merged['days'] = fallbackArgs['days'];
    merged['target_currency'] = fallbackArgs['target_currency'];
    merged['user_budget_usd'] = fallbackArgs['user_budget_usd'];
    if (toolName == saveTripPlanToolName) {
      merged['destination'] = fallbackArgs['destination'];
      final candidateSummary = merged['itinerary_summary']?.toString() ?? '';
      final days = (fallbackArgs['days'] as num?)?.toInt() ?? 3;
      if (!_hasValidDayByDayItinerary(candidateSummary, days)) {
        merged['itinerary_summary'] = fallbackArgs['itinerary_summary'];
      }
    }
    return merged;
  }

  String _buildNarrativePrompt({
    required LlmRequest request,
    required String agentHint,
  }) {
    final readiness = evaluateIntakeReadiness(request);
    final isSpanish = readiness.isSpanish;
    final budgetArgs = extractBudgetArgsFromRequest(request);
    final days =
        readiness.detectedDays ?? (budgetArgs['days'] as num?)?.toInt() ?? 4;
    final userPrompt = _extractLatestUserMissionPrompt(request);
    final destination = extractDestinationFromText(
      userPrompt.isNotEmpty
          ? userPrompt
          : (readiness.detectedDestination ?? ''),
    );
    final toolResponse = _extractLatestFunctionResponseMap(request);

    if (agentHint == 'budget_auditor_agent' && toolResponse != null) {
      if (isSpanish) {
        return '''
RESULTADO_HERRAMIENTA `calculate_budget_math`:
${jsonEncode(toolResponse)}

Viaje: $destination ($days días)
Solicitud del viajero: $userPrompt
Escribe en español una Auditoría Financiera concisa en viñetas (PROHIBIDO usar tablas con barras |) resumiendo el costo de hospedaje, alimentación, actividades, reserva de contingencia del 10%, gran total en USD y moneda local, e indica si está DENTRO DEL PRESUPUESTO (WITHIN BUDGET) o SOBRE PRESUPUESTO (OVER BUDGET).''';
      }
      return '''
TOOL_RESULT_SUMMARY for `calculate_budget_math`:
${jsonEncode(toolResponse)}

User mission: $userPrompt
Write a concise bulleted Financial Audit (no markdown pipe tables) summarizing the itemized lodging, dining, activities, 10% contingency reserve, converted currency total, and whether the trip is WITHIN BUDGET or OVER BUDGET.''';
    }

    if (agentHint == 'concierge_agent') {
      final vaultSummary = jsonEncode(<String, dynamic>{
        'status': 'saved',
        'destination': destination,
        'days': days,
      });
      if (isSpanish) {
        return '''
ESTADO_VAULT para `save_trip_plan`:
$vaultSummary

Viaje confirmado en $destination por $days días.
Escribe en español una Guía Ejecutiva del Concierge (PROHIBIDO repetir cifras del presupuesto o escribir tablas) con estas 3 secciones en viñetas:
- **Gastronomía y Platos Típicos**: 3 platos locales imperdibles de $destination y zonas dónde probarlos.
- **Consejos Locales y Logística**: 3 recomendaciones prácticas sobre transporte, mejores horarios para visitar sitios y reservas.
- **Lista de Equipaje**: 4 artículos esenciales para este viaje.''';
      }
      return '''
VAULT_STATUS for `save_trip_plan`:
$vaultSummary

Confirmed trip: $destination for $days days.
Write a concise Executive Concierge Guide in English (DO NOT repeat budget numbers or write tables) with these 3 bulleted sections:
- **Must-Try Local Gastronomy**: 3 signature local dishes in $destination and where to try them.
- **Insider Logistics & Best Hours**: 3 practical tips on local transit, best visiting hours, and reservations.
- **Essential Packing Checklist**: 4 tailored items for this trip.''';
    }

    if (isSpanish) {
      return '''
Destino: $destination
Duración: $days días
Solicitud del viajero: $userPrompt

Escribe INMEDIATAMENTE el itinerario detallado día por día desde el Día 1 hasta el Día $days para $destination en español (sin párrafos de introducción y PROHIBIDO escribir tablas de presupuesto o costos).
Usa exactamente este formato para cada día:
### Día 1: [Nombre de la zona o barrio]
- **Mañana**: [Sitios específicos con nombre propio, plazas o monumentos y qué hacer]
- **Tarde**: [Actividades culturales, playas o museos y zona recomendada para almorzar]
- **Noche**: [Barrio recomendado para cenar, mirador o paseo nocturno]
(Continúa hasta completar los $days días).''';
    }

    return '''
Destination: $destination
Duration: $days days
Traveler mission: $userPrompt

Write IMMEDIATELY the detailed day-by-day itinerary from Day 1 to Day $days for $destination in English (no intro fluff and DO NOT write budget tables or cost numbers).
Use this exact structure for every day:
### Day 1: [Neighborhood or District Name]
- **Morning**: [Specific named landmarks, plazas, or streets and what to do]
- **Afternoon**: [Cultural spots, museums, or beaches and where to have lunch]
- **Evening**: [Recommended dining district, viewpoint, or evening stroll]
(Continue through Day $days).''';
  }

  String _buildConciseSystemInstruction({
    required LlmRequest request,
    required String agentHint,
  }) {
    final isSpanish = evaluateIntakeReadiness(request).isSpanish;
    if (isSpanish) {
      return switch (agentHint) {
        'budget_auditor_agent' => 'You are budget_auditor_agent. Respond in Spanish with a crisp bulleted financial audit using the exact numbers from calculate_budget_math. Do not use markdown pipe tables.',
        'concierge_agent' => 'You are concierge_agent. Respond in Spanish with local gastronomy dishes, insider logistics tips, and a packing checklist. Never repeat budget tables or cost numbers.',
        _ => 'You are scout_agent. Respond in Spanish. Write ONLY a complete Day-by-Day itinerary (Día 1..N) with Morning (Mañana), Afternoon (Tarde), and Evening (Noche) and real named landmarks. Never write budget tables or currency notes.',
      };
    }
    return switch (agentHint) {
      'budget_auditor_agent' => 'You are budget_auditor_agent. Present a crisp bulleted financial audit using the exact numbers from calculate_budget_math. Do not use markdown pipe tables.',
      'concierge_agent' => 'You are concierge_agent. Present local gastronomy dishes, insider logistics tips, and a packing checklist confirming the trip is saved in the Vault. Never repeat budget numbers.',
      _ => 'You are scout_agent. Write ONLY a complete Day-by-Day itinerary (Day 1..N) with Morning, Afternoon, and Evening and real named landmarks. Never write budget tables or cost inputs.',
    };
  }

  String _buildFallbackNarrative({
    required LlmRequest request,
    required String agentHint,
    Object? error,
  }) {
    final readiness = evaluateIntakeReadiness(request);
    final isSpanish = readiness.isSpanish;
    final budgetArgs = extractBudgetArgsFromRequest(request);
    final userPrompt = _extractLatestUserMissionPrompt(request);
    final destination = extractDestinationFromText(
      userPrompt.isNotEmpty
          ? userPrompt
          : (readiness.detectedDestination ?? ''),
    );
    final days =
        readiness.detectedDays ?? (budgetArgs['days'] as num?)?.toInt() ?? 4;
    final currency = (budgetArgs['target_currency'] as String?) ?? 'USD';
    final userBudget =
        (budgetArgs['user_budget_usd'] as num?)?.toDouble() ?? 1200.0;
    final lodging =
        (budgetArgs['lodging_per_night_usd'] as num?)?.toDouble() ?? 135.0;
    final food = (budgetArgs['food_per_day_usd'] as num?)?.toDouble() ?? 55.0;
    final activities =
        (budgetArgs['activities_total_usd'] as num?)?.toDouble() ?? 160.0;

    if (agentHint == 'budget_auditor_agent') {
      final subtotal = (days * lodging) + (days * food) + activities;
      final contingency = subtotal * 0.10;
      final grandTotal = subtotal + contingency;
      if (isSpanish) {
        final status = grandTotal <= userBudget
            ? 'DENTRO DEL PRESUPUESTO (WITHIN BUDGET)'
            : 'SOBRE PRESUPUESTO (OVER BUDGET)';
        return '''
- **Destino Auditado**: $destination ($days días • moneda objetivo `$currency`)
- **Hospedaje**: \$${lodging.toStringAsFixed(0)}/noche × $days noches = \$${(days * lodging).toStringAsFixed(2)} USD
- **Alimentación**: \$${food.toStringAsFixed(0)}/día × $days días = \$${(days * food).toStringAsFixed(2)} USD
- **Actividades y Entradas**: \$${activities.toStringAsFixed(2)} USD
- **Reserva de Contingencia (10%)**: \$${contingency.toStringAsFixed(2)} USD
- **Gran Total Auditado**: **\$${grandTotal.toStringAsFixed(2)} USD** vs. Presupuesto **\$${userBudget.toStringAsFixed(2)} USD** (**$status**)''';
      }
      final status = grandTotal <= userBudget ? 'WITHIN BUDGET' : 'OVER BUDGET';
      return '''
- **Destination**: $destination ($days days • `$currency`)
- **Lodging**: \$${lodging.toStringAsFixed(0)}/night × $days = \$${(days * lodging).toStringAsFixed(2)} USD
- **Dining**: \$${food.toStringAsFixed(0)}/day × $days = \$${(days * food).toStringAsFixed(2)} USD
- **Activities**: \$${activities.toStringAsFixed(2)} USD
- **10% Contingency**: \$${contingency.toStringAsFixed(2)} USD
- **Grand Total**: **\$${grandTotal.toStringAsFixed(2)} USD** vs. Budget **\$${userBudget.toStringAsFixed(2)} USD** (**$status**)''';
    }

    if (agentHint == 'concierge_agent') {
      return buildRichConciergeGuideFallback(
        destination: destination,
        days: days,
        currency: currency,
        isSpanish: isSpanish,
      );
    }

    return buildRichScoutDayByDayFallback(
      destination: destination,
      days: days,
      isSpanish: isSpanish,
    );
  }

  /// Builds a rich, budget-free Concierge Guide with Local Gastronomy,
  /// Insider Logistics, and Packing Checklist in Spanish or English.
  static String buildRichConciergeGuideFallback({
    required String destination,
    required int days,
    required String currency,
    required bool isSpanish,
  }) {
    final lower = destination.toLowerCase();
    if (isSpanish) {
      final dishes = lower.contains('cartagena')
          ? '**Posta negra cartagenera**, **pargo rojo frito con arroz con coco y patacones**, **ceviche de camarón** y **arepa de huevo** en Getsemaní y San Diego.'
          : (lower.contains('kyoto') || lower.contains('kioto'))
          ? '**Kaiseki ryori**, **ramen kyotoense**, **yudofu (tofu caliente en Arashiyama)** y postres de **té matcha de Uji** en el Mercado Nishiki y Pontocho.'
          : 'Platos tradicionales de la región en el mercado histórico, especialidades callejeras locales y cena de autor en el casco antiguo de **$destination**.';

      return '''
- **Estado del Vault**: Tu plan de **$days días en $destination** quedó guardado en tu **Saved Trips Vault** local.
- **Gastronomía y Platos Típicos**: $dishes
- **Consejos Locales y Logística**:
  1. Visita los monumentos principales antes de las 8:30 AM para evitar el calor y las filas.
  2. Usa transporte oficial o caminatas guiadas dentro de los barrios históricos y lleva efectivo en `$currency` para mercados locales.
  3. Reserva restaurantes emblemáticos y excursiones con al menos 3-5 días de anticipación.
- **Lista de Equipaje**:
  - Pasaporte/documento e itinerario offline guardado en la app
  - Calzado cómodo para largas caminatas y ropa fresca/transpirable
  - Bloqueador solar, gafas de sol y botella reutilizable
  - Batería portátil (power bank) y adaptador universal''';
    }

    final dishes = lower.contains('cartagena')
        ? '**Posta negra cartagenera**, **fried red snapper with coconut rice & patacones**, and **arepa de huevo** around San Diego and Getsemaní.'
        : (lower.contains('kyoto') || lower.contains('kioto'))
        ? '**Kaiseki multi-course dining**, **Nishiki Market street skewers**, **Arashiyama yudofu**, and ceremonial **Uji matcha desserts**.'
        : 'Signature regional dishes at the central market, artisan street food, and a traditional tasting dinner in **$destination**.';

    return '''
- **Vault Status**: Saved your **$days-day $destination** dossier to the on-device **Saved Trips Vault**.
- **Must-Try Local Gastronomy**: $dishes
- **Insider Logistics & Best Hours**:
  1. Arrive at flagship landmarks before 8:30 AM to beat crowds and midday heat.
  2. Keep contactless transit or small notes in `$currency` ready for local markets and neighborhood hops.
  3. Reserve signature dining and boat/rail excursions 5-7 days ahead.
- **Essential Packing Checklist**:
  - Passport & offline itinerary copy in Vault
  - Broken-in walking shoes for historic cobblestone streets
  - Weather-appropriate breathable layers & sun protection
  - Universal power adapter & 10,000mAh power bank''';
  }

  String _prefixWithAgentHeader({
    required String text,
    required String agentHint,
  }) {
    final header = switch (agentHint) {
      'coordinator_agent' => coordinatorHeader,
      'budget_auditor_agent' => budgetHeader,
      'concierge_agent' => conciergeHeader,
      _ => scoutHeader,
    };
    final trimmedHeader = header.trim();
    if (text.contains(trimmedHeader)) {
      return text;
    }
    return '$header$text';
  }

  static String _extractLatestUserMissionPrompt(LlmRequest request) {
    final activeMessages = extractActiveIntakeUserMessages(request);
    if (activeMessages.isNotEmpty) {
      return activeMessages.join(' | ');
    }
    return _flattenRequestText(request);
  }

  static Map<String, dynamic>? _extractLatestFunctionResponseMap(
    LlmRequest request,
  ) {
    for (var i = request.contents.length - 1; i >= 0; i--) {
      final content = request.contents[i];
      for (final part in content.parts) {
        if (part.functionResponse != null) {
          return part.functionResponse!.response;
        }
      }
    }
    return null;
  }

  static String _flattenRequestText(LlmRequest request) {
    final buffer = StringBuffer();
    if (request.config.systemInstruction != null) {
      buffer.writeln(request.config.systemInstruction);
    }
    for (final content in request.contents) {
      for (final part in content.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          buffer.writeln(part.text);
        }
        if (part.functionResponse != null) {
          buffer.writeln(jsonEncode(part.functionResponse!.response));
        }
      }
    }
    return buffer.toString();
  }

  static int? _extractDays(String text) {
    final explicit = EvaluateTripIntakeUseCase.detectExplicitDays(text);
    if (explicit != null) return explicit;

    final match = RegExp(
      r'\bdays[`"\s:=]+(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value >= 1 && value <= 30) {
        return value;
      }
    }
    return null;
  }

  static String? _extractCurrency(String text) {
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
    if (RegExp(r'CONVERT\s+TO\s+USD\b').hasMatch(upper) ||
        RegExp(r'TARGET_CURRENCY[`"\s:=]+USD\b').hasMatch(upper)) {
      return 'USD';
    }
    return null;
  }

  static double? _extractUserBudgetUsd(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'(?:budget|presupuesto)(?:\s+total)?(?:\s+of|\s+de)?\s*\$?\s*([\d,]+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'user_budget_usd[`"\s:=]*\$?\s*([\d,]+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'\$\s*([\d,]+(?:\.\d+)?)\s*(?:USD|d[oó]lares?|dollars?)?',
        caseSensitive: false,
      ),
      RegExp(
        r'\b([\d,]+(?:\.\d+)?)\s*(?:USD|d[oó]lares?|dollars?)\b',
        caseSensitive: false,
      ),
    ];
    for (final regex in patterns) {
      final match = regex.firstMatch(text);
      if (match != null) {
        final cleaned = match.group(1)!.replaceAll(',', '');
        final parsed = double.tryParse(cleaned);
        if (parsed != null && parsed >= 100) {
          return parsed;
        }
      }
    }
    return null;
  }

  static double? _extractLabeledNumber(
    String text, {
    required List<RegExp> patterns,
  }) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final cleaned = match.group(1)!.replaceAll(',', '');
        final value = double.tryParse(cleaned);
        if (value != null && value > 0) {
          return value;
        }
      }
    }
    return null;
  }

  static String _defaultCurrencyForDestination(String destination) {
    if (destination.contains('Japan')) return 'JPY';
    if (destination.contains('Colombia')) return 'COP';
    if (destination.contains('Portugal') ||
        destination.contains('Iceland') ||
        destination.contains('France') ||
        destination.contains('Italy') ||
        destination.contains('Spain')) {
      return 'EUR';
    }
    if (destination.contains('United Kingdom')) return 'GBP';
    if (destination.contains('Mexico')) return 'MXN';
    return 'USD';
  }

  static double _defaultLodgingPerNight(String destination) {
    if (destination.contains('Cartagena') || destination.contains('Colombia')) {
      return 110.0;
    }
    if (destination.contains('Kyoto') || destination.contains('Japan')) {
      return 145.0;
    }
    if (destination.contains('Lisbon') || destination.contains('Portugal')) {
      return 135.0;
    }
    if (destination.contains('Reykjavik') || destination.contains('Iceland')) {
      return 210.0;
    }
    return 130.0;
  }

  static double _defaultFoodPerDay(String destination) {
    if (destination.contains('Cartagena') || destination.contains('Colombia')) {
      return 45.0;
    }
    if (destination.contains('Kyoto') || destination.contains('Japan')) {
      return 55.0;
    }
    if (destination.contains('Lisbon') || destination.contains('Portugal')) {
      return 50.0;
    }
    if (destination.contains('Reykjavik') || destination.contains('Iceland')) {
      return 75.0;
    }
    return 50.0;
  }

  static double _defaultActivitiesTotal(String destination, int days) {
    if (destination.contains('Cartagena') || destination.contains('Colombia')) {
      return 120.0;
    }
    if (destination.contains('Kyoto') || destination.contains('Japan')) {
      return 160.0;
    }
    if (destination.contains('Lisbon') || destination.contains('Portugal')) {
      return 150.0;
    }
    if (destination.contains('Reykjavik') || destination.contains('Iceland')) {
      return 260.0;
    }
    return (days * 40).toDouble();
  }
}

class _DayRoutePlan {
  const _DayRoutePlan({
    required this.title,
    required this.morning,
    required this.afternoon,
    required this.evening,
  });

  final String title;
  final String morning;
  final String afternoon;
  final String evening;
}
