/// Evaluates whether the user has provided all 3 required trip intake parameters
/// (Destination, Duration in days, and Budget) across one or more conversational turns.
class TripIntakeReadiness {
  const TripIntakeReadiness({
    required this.hasDestination,
    required this.hasDays,
    required this.hasBudget,
    required this.isSpanish,
    required this.aggregatedUserText,
    this.detectedDestination,
    this.detectedDays,
    this.detectedBudget,
  });

  final bool hasDestination;
  final bool hasDays;
  final bool hasBudget;
  final bool isSpanish;
  final String aggregatedUserText;
  final String? detectedDestination;
  final int? detectedDays;
  final double? detectedBudget;

  bool get isComplete => hasDestination && hasDays && hasBudget;

  List<String> get missingFields {
    final missing = <String>[];
    if (!hasDestination) missing.add('destination');
    if (!hasDays) missing.add('days');
    if (!hasBudget) missing.add('budget');
    return missing;
  }
}

/// Pure domain use case that evaluates whether conversational user intake text
/// contains all 3 required trip parameters: Destination, Duration (days), and Budget.
class EvaluateTripIntakeUseCase {
  const EvaluateTripIntakeUseCase();

  static const List<String> knownDestinations = <String>[
    'kyoto',
    'kioto',
    'tokyo',
    'tokio',
    'osaka',
    'japan',
    'japón',
    'japon',
    'cartagena',
    'bogota',
    'bogotá',
    'medellin',
    'medellín',
    'santa marta',
    'san andrés',
    'san andres',
    'colombia',
    'lisbon',
    'lisboa',
    'porto',
    'oporto',
    'portugal',
    'reykjavik',
    'reikiavik',
    'iceland',
    'islandia',
    'paris',
    'parís',
    'france',
    'francia',
    'rome',
    'roma',
    'milan',
    'milán',
    'venice',
    'venecia',
    'florence',
    'florencia',
    'italy',
    'italia',
    'madrid',
    'barcelona',
    'sevilla',
    'seville',
    'spain',
    'españa',
    'espana',
    'london',
    'londres',
    'reino unido',
    'berlin',
    'berlín',
    'munich',
    'múnich',
    'germany',
    'alemania',
    'amsterdam',
    'ámsterdam',
    'cancun',
    'cancún',
    'cdmx',
    'ciudad de méxico',
    'ciudad de mexico',
    'mexico city',
    'mexico',
    'méxico',
    'tulum',
    'new york',
    'nueva york',
    'nyc',
    'miami',
    'los angeles',
    'san francisco',
    'orlando',
    'chicago',
    'las vegas',
    'boston',
    'buenos aires',
    'argentina',
    'bariloche',
    'mendoza',
    'lima',
    'cusco',
    'cuzco',
    'machu picchu',
    'peru',
    'perú',
    'santiago',
    'chile',
    'rio de janeiro',
    'río de janeiro',
    'sao paulo',
    'são paulo',
    'brazil',
    'brasil',
    'seoul',
    'seúl',
    'korea',
    'corea',
    'bangkok',
    'thailand',
    'tailandia',
    'bali',
    'singapore',
    'singapur',
    'dubai',
    'dubái',
    'cairo',
    'el cairo',
    'egypt',
    'egipto',
    'istanbul',
    'estambul',
    'athens',
    'atenas',
    'greece',
    'grecia',
    'santorini',
    'prague',
    'praga',
    'vienna',
    'viena',
    'zurich',
    'zúrich',
    'geneva',
    'ginebra',
    'switzerland',
    'suiza',
    'sydney',
    'sídney',
    'melbourne',
    'australia',
    'toronto',
    'vancouver',
    'montreal',
    'canada',
    'canadá',
    'havana',
    'la habana',
    'punta cana',
    'costa rica',
    'panama',
    'panamá',
    'quito',
    'galapagos',
    'galápagos',
  ];

  static const Set<String> _destinationStopwords = <String>{
    'hola',
    'buenos',
    'buenas',
    'dias',
    'días',
    'noches',
    'semanas',
    'semana',
    'presupuesto',
    'total',
    'usd',
    'eur',
    'cop',
    'mxn',
    'jpy',
    'gbp',
    'un',
    'una',
    'unos',
    'unas',
    'mi',
    'mis',
    'tu',
    'el',
    'la',
    'los',
    'las',
    'por',
    'con',
    'para',
    'the',
    'my',
    'our',
    'a',
    'an',
    'budget',
    'days',
    'nights',
    'weeks',
    'week',
    'weekend',
    'vacaciones',
    'vacation',
    'trip',
    'viaje',
    'viajar',
    'planear',
    'planificar',
    'plan',
  };

  /// Evaluates [aggregatedText] and returns a [TripIntakeReadiness] value object.
  TripIntakeReadiness call(String aggregatedText) =>
      evaluateText(aggregatedText);

  /// Static convenience entry point for evaluating [aggregatedText].
  static TripIntakeReadiness evaluateText(String aggregatedText) {
    final trimmed = aggregatedText.trim();
    final lower = trimmed.toLowerCase();

    final isSpanish = RegExp(
      r'\b(hola|buenos|buenas|quiero|viajar|viaje|ir|d[ií]as?|presupuesto|tengo|noches?|d[oó]lares?|euros?|pesos?|semana|fin de semana|ayuda|planear|planificar|gustar[ií]a|conocer|visitar|cu[aá]nto|d[oó]nde)\b|[áéíóúñ¿¡]',
      caseSensitive: false,
    ).hasMatch(lower);

    final detectedDestination = detectExplicitDestination(trimmed);
    final detectedDays = detectExplicitDays(trimmed);
    final detectedBudget = detectExplicitBudget(trimmed);

    return TripIntakeReadiness(
      hasDestination: detectedDestination != null,
      hasDays: detectedDays != null,
      hasBudget: detectedBudget != null,
      isSpanish: isSpanish,
      aggregatedUserText: trimmed,
      detectedDestination: detectedDestination,
      detectedDays: detectedDays,
      detectedBudget: detectedBudget,
    );
  }

  /// Strictly detects an explicit destination from [text], or returns `null`
  /// if none was provided.
  static String? detectExplicitDestination(String text) {
    if (text.trim().isEmpty) return null;
    final lower = text.toLowerCase();

    for (final known in knownDestinations) {
      final pattern = RegExp(
        '(?:^|[^a-záéíóúñ])${RegExp.escape(known)}(?:\$|[^a-záéíóúñ])',
        caseSensitive: false,
      );
      if (pattern.hasMatch(lower)) {
        return known[0].toUpperCase() + known.substring(1);
      }
    }

    final prepMatch = RegExp(
      r'\b(?:ir\s+a|viajar\s+a|viaje\s+a|visitar|conocer|destino\s*:?\s*|travel\s+to|trip\s+to|visit|go\s+to|going\s+to|fly\s+to|in)\s+([A-ZÁÉÍÓÚÑa-záéíóúñ]{3,}(?:\s+[A-ZÁÉÍÓÚÑa-záéíóúñ]{3,})?)',
      caseSensitive: false,
    ).firstMatch(text);

    if (prepMatch != null) {
      final rawCandidate = prepMatch.group(1)!.trim();
      final words = rawCandidate
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final filteredWords = <String>[];
      for (final word in words) {
        final cleanWord = word.toLowerCase().replaceAll(
          RegExp(r'[^a-záéíóúñ]'),
          '',
        );
        if (cleanWord.isEmpty || _destinationStopwords.contains(cleanWord)) {
          break;
        }
        filteredWords.add(word);
      }
      if (filteredWords.isNotEmpty) {
        return filteredWords.join(' ');
      }
    }

    return null;
  }

  /// Strictly detects an explicit trip duration in days from [text], or returns
  /// `null` if none was provided.
  static int? detectExplicitDays(String text) {
    if (text.trim().isEmpty) return null;
    final lower = text.toLowerCase();

    final dayMatch = RegExp(
      r'\b(\d+)\s*(?:-|\s)?\s*(?:d[ií]as?|days?|noches?|nights?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (dayMatch != null) {
      final value = int.tryParse(dayMatch.group(1)!);
      if (value != null && value >= 1 && value <= 60) {
        return value;
      }
    }

    final weekMatch = RegExp(
      r'\b(\d+)\s*(?:-|\s)?\s*(?:semanas?|weeks?)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (weekMatch != null) {
      final weeks = int.tryParse(weekMatch.group(1)!);
      if (weeks != null && weeks >= 1 && weeks <= 8) {
        return weeks * 7;
      }
    }

    if (RegExp(
      r'\b(fin\s+de\s+semana|weekend)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 3;
    }
    if (RegExp(
      r'\b(una\s+semana|one\s+week|a\s+week)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return 7;
    }

    const wordMap = <String, int>{
      'dos': 2,
      'two': 2,
      'tres': 3,
      'three': 3,
      'cuatro': 4,
      'four': 4,
      'cinco': 5,
      'five': 5,
      'seis': 6,
      'six': 6,
      'siete': 7,
      'seven': 7,
      'diez': 10,
      'ten': 10,
    };
    for (final entry in wordMap.entries) {
      if (RegExp(
        '\\b${entry.key}\\s+(?:d[ií]as?|days?|noches?|nights?)\\b',
        caseSensitive: false,
      ).hasMatch(lower)) {
        return entry.value;
      }
    }

    return null;
  }

  /// Strictly detects an explicit trip budget from [text], or returns `null`
  /// if none was provided.
  static double? detectExplicitBudget(String text) {
    if (text.trim().isEmpty) return null;

    final patterns = <RegExp>[
      RegExp(r'\$\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
      RegExp(
        r'\b([\d,]+(?:\.\d+)?)\s*(?:usd|eur|cop|mxn|jpy|gbp|cad|aud|chf|d[oó]lares?|dollars?|euros?|pesos?|yenes?)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:presupuesto|budget)\s*(?:total)?\s*(?:de|of|around|unos|:)?\s*\$?\s*([\d,]+(?:\.\d+)?)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:tengo|con|have)\s*(?:unos|around)?\s*\$\s*([\d,]+(?:\.\d+)?)\b',
        caseSensitive: false,
      ),
    ];

    for (final regex in patterns) {
      final match = regex.firstMatch(text);
      if (match != null) {
        final cleaned = match.group(1)!.replaceAll(',', '');
        final parsed = double.tryParse(cleaned);
        if (parsed != null && parsed >= 50) {
          return parsed;
        }
      }
    }

    return null;
  }
}
