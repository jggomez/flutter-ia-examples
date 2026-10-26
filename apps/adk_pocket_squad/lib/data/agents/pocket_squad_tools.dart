import 'package:adk_dart/adk_core.dart';

import '../../domain/models/budget_breakdown.dart';
import '../../domain/models/saved_trip.dart';
import '../../domain/use_cases/calculate_trip_budget_use_case.dart';
import '../../domain/use_cases/save_trip_plan_use_case.dart';
import '../services/app_storage_service.dart';

/// Authentic `FunctionTool` implementations for the Pocket Squad multi-agent
/// pipeline:
/// 1. `calculate_budget_math` (used by `budget_auditor_agent`): deterministic
///    multi-day arithmetic, 10% contingency buffer, offline currency conversion,
///    and target budget delta verification.
/// 2. `save_trip_plan` (used by `concierge_agent`): local device persistence of
///    the finalized [SavedTrip] dossier into [AppStorageService].
class PocketSquadTools {
  PocketSquadTools({
    required this.storageService,
    CalculateTripBudgetUseCase? calculateTripBudgetUseCase,
    SaveTripPlanUseCase? saveTripPlanUseCase,
    this.engineLabelProvider,
    this.onBudgetCalculated,
    this.onTripSaved,
  }) : calculateTripBudgetUseCase =
           calculateTripBudgetUseCase ?? const CalculateTripBudgetUseCase(),
       saveTripPlanUseCase =
           saveTripPlanUseCase ??
           SaveTripPlanUseCase(storageService: storageService) {
    calculateBudgetMathTool = FunctionTool(
      name: calculateBudgetToolName,
      description:
          'Computes exact multi-day travel costs in USD, adds a 10% contingency '
          'reserve, converts the grand total into the target currency (USD, EUR, '
          'JPY, GBP, MXN, COP, CAD, AUD, CHF), and checks whether the trip is '
          'within the user budget.',
      declaration: FunctionDeclaration(
        name: calculateBudgetToolName,
        description:
            'Deterministically computes itemized trip totals, 10% contingency '
            'buffer, currency conversion, and budget compliance.',
        parameters: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'days': <String, dynamic>{
              'type': 'integer',
              'description': 'Total number of trip days (e.g. 4).',
            },
            'lodging_per_night_usd': <String, dynamic>{
              'type': 'number',
              'description': 'Estimated lodging cost per night in USD.',
            },
            'food_per_day_usd': <String, dynamic>{
              'type': 'number',
              'description':
                  'Estimated dining and street food cost per day in USD.',
            },
            'activities_total_usd': <String, dynamic>{
              'type': 'number',
              'description':
                  'Total estimated activities and transit cost in USD.',
            },
            'target_currency': <String, dynamic>{
              'type': 'string',
              'description':
                  'ISO currency code (USD, EUR, JPY, GBP, MXN, COP).',
            },
            'user_budget_usd': <String, dynamic>{
              'type': 'number',
              'description': 'Target maximum user budget in USD.',
            },
          },
        },
      ),
      func: calculateBudgetMath,
    );

    saveTripPlanTool = FunctionTool(
      name: saveTripPlanToolName,
      description:
          'Persists the finalized travel itinerary, packing checklist, concierge '
          'notes, and audited budget breakdown into the local Saved Trips Vault.',
      declaration: FunctionDeclaration(
        name: saveTripPlanToolName,
        description: 'Saves a finalized travel plan and budget dossier to local device storage.',
        parameters: <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'destination': <String, dynamic>{
              'type': 'string',
              'description':
                  'Destination city and country (e.g. Kyoto, Japan).',
            },
            'days': <String, dynamic>{
              'type': 'integer',
              'description': 'Number of days for the trip.',
            },
            'itinerary_summary': <String, dynamic>{
              'type': 'string',
              'description': 'Concise summary of the day-by-day route.',
            },
            'packing_checklist': <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
              'description': 'List of essential packing items.',
            },
            'concierge_notes': <String, dynamic>{
              'type': 'string',
              'description': 'Insider concierge tips and reservation guidance.',
            },
            'lodging_per_night_usd': <String, dynamic>{
              'type': 'number',
              'description': 'Nightly lodging cost in USD.',
            },
            'food_per_day_usd': <String, dynamic>{
              'type': 'number',
              'description': 'Daily food cost in USD.',
            },
            'activities_total_usd': <String, dynamic>{
              'type': 'number',
              'description': 'Total activities cost in USD.',
            },
            'target_currency': <String, dynamic>{
              'type': 'string',
              'description': 'Target ISO currency code.',
            },
            'user_budget_usd': <String, dynamic>{
              'type': 'number',
              'description': 'User budget cap in USD.',
            },
          },
        },
      ),
      func: saveTripPlan,
    );
  }

  static const String calculateBudgetToolName = 'calculate_budget_math';
  static const String saveTripPlanToolName = 'save_trip_plan';

  final AppStorageService storageService;
  final CalculateTripBudgetUseCase calculateTripBudgetUseCase;
  final SaveTripPlanUseCase saveTripPlanUseCase;
  final String Function()? engineLabelProvider;
  final void Function(BudgetBreakdown breakdown)? onBudgetCalculated;
  final void Function(SavedTrip trip)? onTripSaved;

  late final FunctionTool calculateBudgetMathTool;
  late final FunctionTool saveTripPlanTool;

  BudgetBreakdown? _latestBudgetBreakdown;
  SavedTrip? _latestSavedTrip;

  /// Latest [BudgetBreakdown] computed by [calculateBudgetMath].
  BudgetBreakdown? get latestBudgetBreakdown => _latestBudgetBreakdown;

  /// Latest [SavedTrip] persisted by [saveTripPlan].
  SavedTrip? get latestSavedTrip => _latestSavedTrip;

  /// Both authentic tools registered across the squad.
  List<FunctionTool> get allTools => <FunctionTool>[
    calculateBudgetMathTool,
    saveTripPlanTool,
  ];

  /// Executes `calculate_budget_math` and notifies [onBudgetCalculated].
  Future<Map<String, dynamic>> calculateBudgetMath(
    Map<String, dynamic> args,
  ) async {
    final days = _readInt(
      args,
      'days',
      fallbackKey: 'trip_days',
      defaultValue: 4,
    );
    final lodgingPerNight = _readDouble(
      args,
      'lodging_per_night_usd',
      fallbackKey: 'lodgingPerNightUsd',
      defaultValue: 135.0,
    );
    final foodPerDay = _readDouble(
      args,
      'food_per_day_usd',
      fallbackKey: 'foodPerDayUsd',
      defaultValue: 55.0,
    );
    final activitiesTotal = _readDouble(
      args,
      'activities_total_usd',
      fallbackKey: 'activitiesTotalUsd',
      defaultValue: 160.0,
    );
    final targetCurrency = _readString(
      args,
      'target_currency',
      fallbackKey: 'targetCurrency',
      defaultValue: 'USD',
    ).toUpperCase();
    final userBudget = _readNullableDouble(
      args,
      'user_budget_usd',
      fallbackKey: 'userBudgetUsd',
    );
    final exchangeRateOverride = _readNullableDouble(
      args,
      'exchange_rate_override',
      fallbackKey: 'exchangeRateOverride',
    );

    final breakdown = calculateTripBudgetUseCase(
      days: days,
      lodgingPerNightUsd: lodgingPerNight,
      foodPerDayUsd: foodPerDay,
      activitiesTotalUsd: activitiesTotal,
      targetCurrency: targetCurrency,
      userBudgetUsd: userBudget,
      exchangeRateOverride: exchangeRateOverride,
    );

    _latestBudgetBreakdown = breakdown;
    onBudgetCalculated?.call(breakdown);
    return breakdown.toJson();
  }

  /// Executes `save_trip_plan`, persists the [SavedTrip] via [saveTripPlanUseCase],
  /// and notifies [onTripSaved].
  Future<Map<String, dynamic>> saveTripPlan(Map<String, dynamic> args) async {
    final destination = _readString(
      args,
      'destination',
      fallbackKey: 'city',
      defaultValue: 'Kyoto, Japan',
    );
    final days = _readInt(
      args,
      'days',
      fallbackKey: 'trip_days',
      defaultValue: _latestBudgetBreakdown?.days ?? 4,
    );

    final BudgetBreakdown breakdown =
        _latestBudgetBreakdown ??
        calculateTripBudgetUseCase(
          days: days,
          lodgingPerNightUsd: _readDouble(
            args,
            'lodging_per_night_usd',
            fallbackKey: 'lodgingPerNightUsd',
            defaultValue: 135.0,
          ),
          foodPerDayUsd: _readDouble(
            args,
            'food_per_day_usd',
            fallbackKey: 'foodPerDayUsd',
            defaultValue: 55.0,
          ),
          activitiesTotalUsd: _readDouble(
            args,
            'activities_total_usd',
            fallbackKey: 'activitiesTotalUsd',
            defaultValue: 160.0,
          ),
          targetCurrency: _readString(
            args,
            'target_currency',
            fallbackKey: 'targetCurrency',
            defaultValue: 'USD',
          ),
          userBudgetUsd: _readNullableDouble(
            args,
            'user_budget_usd',
            fallbackKey: 'userBudgetUsd',
          ),
        );

    final itinerarySummary = _readString(
      args,
      'itinerary_summary',
      fallbackKey: 'itinerarySummary',
      defaultValue:
          '$days-day curated neighborhood, cultural, and culinary itinerary in $destination.',
    );

    final rawChecklist = args['packing_checklist'] ?? args['packingChecklist'];
    final List<String> packingChecklist;
    if (rawChecklist is List && rawChecklist.isNotEmpty) {
      packingChecklist = rawChecklist
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } else {
      packingChecklist = const <String>[
        'Passport & offline reservation confirmations',
        'Universal power adapter & portable battery bank',
        'Comfortable walking shoes for daily neighborhood exploration',
        'Packable weather layer & local transit card',
      ];
    }

    final conciergeNotes = _readString(
      args,
      'concierge_notes',
      fallbackKey: 'conciergeNotes',
      defaultValue: 'Book signature cultural entries and popular dining 7-14 days in advance.',
    );

    final engineLabel =
        engineLabelProvider?.call() ??
        _readString(
          args,
          'engine_label',
          fallbackKey: 'engineLabel',
          defaultValue: 'On-Device Gemma 4 E2B (LiteRT-LM)',
        );

    final trip = await saveTripPlanUseCase(
      destination: destination,
      days: days,
      itinerarySummary: itinerarySummary,
      packingChecklist: packingChecklist,
      budgetBreakdown: breakdown,
      conciergeNotes: conciergeNotes,
      engineLabel: engineLabel,
    );

    _latestSavedTrip = trip;
    onTripSaved?.call(trip);

    return <String, dynamic>{'status': 'saved', 'trip': trip.toJson()};
  }

  static int _readInt(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
    required int defaultValue,
  }) {
    final raw = map[key] ?? (fallbackKey != null ? map[fallbackKey] : null);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? defaultValue;
    return defaultValue;
  }

  static double _readDouble(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
    required double defaultValue,
  }) {
    final raw = map[key] ?? (fallbackKey != null ? map[fallbackKey] : null);
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      return double.tryParse(raw.replaceAll(',', '').trim()) ?? defaultValue;
    }
    return defaultValue;
  }

  static double? _readNullableDouble(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
  }) {
    final raw = map[key] ?? (fallbackKey != null ? map[fallbackKey] : null);
    if (raw == null) return null;
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      return double.tryParse(raw.replaceAll(',', '').trim());
    }
    return null;
  }

  static String _readString(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
    required String defaultValue,
  }) {
    final raw = map[key] ?? (fallbackKey != null ? map[fallbackKey] : null);
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return defaultValue;
  }
}
