import '../models/budget_breakdown.dart';

/// Pure domain use case that deterministically calculates a multi-day
/// [BudgetBreakdown] with a 10% contingency reserve, target currency
/// conversion, and user budget compliance delta.
class CalculateTripBudgetUseCase {
  const CalculateTripBudgetUseCase();

  BudgetBreakdown call({
    required int days,
    required double lodgingPerNightUsd,
    required double foodPerDayUsd,
    required double activitiesTotalUsd,
    String targetCurrency = 'USD',
    double? userBudgetUsd,
    double? exchangeRateOverride,
  }) {
    return BudgetBreakdown.calculate(
      days: days,
      lodgingPerNightUsd: lodgingPerNightUsd,
      foodPerDayUsd: foodPerDayUsd,
      activitiesTotalUsd: activitiesTotalUsd,
      targetCurrency: targetCurrency,
      userBudgetUsd: userBudgetUsd,
      exchangeRateOverride: exchangeRateOverride,
    );
  }
}
