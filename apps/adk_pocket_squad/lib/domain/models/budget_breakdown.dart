/// Deterministic multi-day travel budget calculation and currency breakdown.
class BudgetBreakdown {
  const BudgetBreakdown({
    required this.days,
    required this.lodgingPerNightUsd,
    required this.foodPerDayUsd,
    required this.activitiesTotalUsd,
    required this.lodgingTotalUsd,
    required this.foodTotalUsd,
    required this.subtotalUsd,
    required this.contingencyBufferUsd,
    required this.grandTotalUsd,
    required this.targetCurrency,
    required this.exchangeRate,
    required this.convertedGrandTotal,
    required this.userBudgetUsd,
    required this.budgetDeltaUsd,
    required this.withinBudget,
  });

  /// Reference offline exchange rates relative to 1.0 USD.
  static const Map<String, double> usdExchangeRates = <String, double>{
    'USD': 1.0,
    'EUR': 0.92,
    'JPY': 153.50,
    'GBP': 0.79,
    'MXN': 19.80,
    'COP': 4250.0,
    'CAD': 1.38,
    'AUD': 1.52,
    'CHF': 0.88,
  };

  /// Deterministically computes all itemized totals, 10% contingency buffer,
  /// target currency conversion, and budget delta.
  factory BudgetBreakdown.calculate({
    required int days,
    required double lodgingPerNightUsd,
    required double foodPerDayUsd,
    required double activitiesTotalUsd,
    String targetCurrency = 'USD',
    double? userBudgetUsd,
    double? exchangeRateOverride,
  }) {
    final safeDays = days < 1 ? 1 : days;
    final lodgingTotal = _round2(safeDays * lodgingPerNightUsd);
    final foodTotal = _round2(safeDays * foodPerDayUsd);
    final activitiesTotal = _round2(activitiesTotalUsd);
    final subtotal = _round2(lodgingTotal + foodTotal + activitiesTotal);
    final contingency = _round2(subtotal * 0.10);
    final grandTotal = _round2(subtotal + contingency);

    final normalizedCurrency = targetCurrency.trim().toUpperCase().isEmpty
        ? 'USD'
        : targetCurrency.trim().toUpperCase();
    final rate =
        exchangeRateOverride ?? usdExchangeRates[normalizedCurrency] ?? 1.0;
    final convertedTotal = _round2(grandTotal * rate);

    final effectiveUserBudget = _round2(userBudgetUsd ?? grandTotal);
    final delta = _round2(effectiveUserBudget - grandTotal);

    return BudgetBreakdown(
      days: safeDays,
      lodgingPerNightUsd: _round2(lodgingPerNightUsd),
      foodPerDayUsd: _round2(foodPerDayUsd),
      activitiesTotalUsd: activitiesTotal,
      lodgingTotalUsd: lodgingTotal,
      foodTotalUsd: foodTotal,
      subtotalUsd: subtotal,
      contingencyBufferUsd: contingency,
      grandTotalUsd: grandTotal,
      targetCurrency: normalizedCurrency,
      exchangeRate: rate,
      convertedGrandTotal: convertedTotal,
      userBudgetUsd: effectiveUserBudget,
      budgetDeltaUsd: delta,
      withinBudget: grandTotal <= effectiveUserBudget,
    );
  }

  final int days;
  final double lodgingPerNightUsd;
  final double foodPerDayUsd;
  final double activitiesTotalUsd;
  final double lodgingTotalUsd;
  final double foodTotalUsd;
  final double subtotalUsd;
  final double contingencyBufferUsd;
  final double grandTotalUsd;
  final String targetCurrency;
  final double exchangeRate;
  final double convertedGrandTotal;
  final double userBudgetUsd;
  final double budgetDeltaUsd;
  final bool withinBudget;

  BudgetBreakdown copyWith({
    int? days,
    double? lodgingPerNightUsd,
    double? foodPerDayUsd,
    double? activitiesTotalUsd,
    double? lodgingTotalUsd,
    double? foodTotalUsd,
    double? subtotalUsd,
    double? contingencyBufferUsd,
    double? grandTotalUsd,
    String? targetCurrency,
    double? exchangeRate,
    double? convertedGrandTotal,
    double? userBudgetUsd,
    double? budgetDeltaUsd,
    bool? withinBudget,
  }) {
    return BudgetBreakdown(
      days: days ?? this.days,
      lodgingPerNightUsd: lodgingPerNightUsd ?? this.lodgingPerNightUsd,
      foodPerDayUsd: foodPerDayUsd ?? this.foodPerDayUsd,
      activitiesTotalUsd: activitiesTotalUsd ?? this.activitiesTotalUsd,
      lodgingTotalUsd: lodgingTotalUsd ?? this.lodgingTotalUsd,
      foodTotalUsd: foodTotalUsd ?? this.foodTotalUsd,
      subtotalUsd: subtotalUsd ?? this.subtotalUsd,
      contingencyBufferUsd: contingencyBufferUsd ?? this.contingencyBufferUsd,
      grandTotalUsd: grandTotalUsd ?? this.grandTotalUsd,
      targetCurrency: targetCurrency ?? this.targetCurrency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      convertedGrandTotal: convertedGrandTotal ?? this.convertedGrandTotal,
      userBudgetUsd: userBudgetUsd ?? this.userBudgetUsd,
      budgetDeltaUsd: budgetDeltaUsd ?? this.budgetDeltaUsd,
      withinBudget: withinBudget ?? this.withinBudget,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'days': days,
      'lodgingPerNightUsd': lodgingPerNightUsd,
      'foodPerDayUsd': foodPerDayUsd,
      'activitiesTotalUsd': activitiesTotalUsd,
      'lodgingTotalUsd': lodgingTotalUsd,
      'foodTotalUsd': foodTotalUsd,
      'subtotalUsd': subtotalUsd,
      'contingencyBufferUsd': contingencyBufferUsd,
      'grandTotalUsd': grandTotalUsd,
      'targetCurrency': targetCurrency,
      'exchangeRate': exchangeRate,
      'convertedGrandTotal': convertedGrandTotal,
      'userBudgetUsd': userBudgetUsd,
      'budgetDeltaUsd': budgetDeltaUsd,
      'withinBudget': withinBudget,
    };
  }

  factory BudgetBreakdown.fromJson(Map<String, dynamic> json) {
    final days = _readInt(
      json,
      'days',
      fallbackKey: 'trip_days',
      defaultValue: 3,
    );
    final lodgingPerNight = _readDouble(
      json,
      'lodgingPerNightUsd',
      fallbackKey: 'lodging_per_night_usd',
      defaultValue: 120.0,
    );
    final foodPerDay = _readDouble(
      json,
      'foodPerDayUsd',
      fallbackKey: 'food_per_day_usd',
      defaultValue: 50.0,
    );
    final activitiesTotal = _readDouble(
      json,
      'activitiesTotalUsd',
      fallbackKey: 'activities_total_usd',
      defaultValue: 150.0,
    );
    final lodgingTotal = _readDouble(
      json,
      'lodgingTotalUsd',
      fallbackKey: 'lodging_total_usd',
      defaultValue: _round2(days * lodgingPerNight),
    );
    final foodTotal = _readDouble(
      json,
      'foodTotalUsd',
      fallbackKey: 'food_total_usd',
      defaultValue: _round2(days * foodPerDay),
    );
    final subtotal = _readDouble(
      json,
      'subtotalUsd',
      fallbackKey: 'subtotal_usd',
      defaultValue: _round2(lodgingTotal + foodTotal + activitiesTotal),
    );
    final contingency = _readDouble(
      json,
      'contingencyBufferUsd',
      fallbackKey: 'contingency_buffer_usd',
      defaultValue: _round2(subtotal * 0.10),
    );
    final grandTotal = _readDouble(
      json,
      'grandTotalUsd',
      fallbackKey: 'grand_total_usd',
      defaultValue: _round2(subtotal + contingency),
    );
    final currency =
        (json['targetCurrency'] as String?) ??
        (json['target_currency'] as String?) ??
        'USD';
    final rate = _readDouble(
      json,
      'exchangeRate',
      fallbackKey: 'exchange_rate',
      defaultValue: usdExchangeRates[currency.toUpperCase()] ?? 1.0,
    );
    final converted = _readDouble(
      json,
      'convertedGrandTotal',
      fallbackKey: 'converted_grand_total',
      defaultValue: _round2(grandTotal * rate),
    );
    final userBudget = _readDouble(
      json,
      'userBudgetUsd',
      fallbackKey: 'user_budget_usd',
      defaultValue: grandTotal,
    );
    final delta = _readDouble(
      json,
      'budgetDeltaUsd',
      fallbackKey: 'budget_delta_usd',
      defaultValue: _round2(userBudget - grandTotal),
    );
    final within =
        (json['withinBudget'] as bool?) ??
        (json['within_budget'] as bool?) ??
        (grandTotal <= userBudget);

    return BudgetBreakdown(
      days: days,
      lodgingPerNightUsd: lodgingPerNight,
      foodPerDayUsd: foodPerDay,
      activitiesTotalUsd: activitiesTotal,
      lodgingTotalUsd: lodgingTotal,
      foodTotalUsd: foodTotal,
      subtotalUsd: subtotal,
      contingencyBufferUsd: contingency,
      grandTotalUsd: grandTotal,
      targetCurrency: currency.toUpperCase(),
      exchangeRate: rate,
      convertedGrandTotal: converted,
      userBudgetUsd: userBudget,
      budgetDeltaUsd: delta,
      withinBudget: within,
    );
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100.0;

  static int _readInt(
    Map<String, dynamic> map,
    String key, {
    String? fallbackKey,
    required int defaultValue,
  }) {
    final raw = map[key] ?? (fallbackKey != null ? map[fallbackKey] : null);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? defaultValue;
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
    if (raw is String) return double.tryParse(raw) ?? defaultValue;
    return defaultValue;
  }
}
