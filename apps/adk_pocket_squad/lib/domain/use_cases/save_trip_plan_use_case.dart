import '../../data/services/app_storage_service.dart';
import '../models/budget_breakdown.dart';
import '../models/saved_trip.dart';

/// Domain use case that constructs a finalized [SavedTrip] dossier and
/// persists it to the local Saved Trips Vault via [AppStorageService].
class SaveTripPlanUseCase {
  const SaveTripPlanUseCase({required this.storageService});

  final AppStorageService storageService;

  Future<SavedTrip> call({
    required String destination,
    required int days,
    required String itinerarySummary,
    required List<String> packingChecklist,
    required BudgetBreakdown budgetBreakdown,
    required String conciergeNotes,
    required String engineLabel,
  }) async {
    final trip = SavedTrip(
      id: 'trip-${DateTime.now().microsecondsSinceEpoch}',
      destination: destination,
      days: days,
      itinerarySummary: itinerarySummary,
      packingChecklist: packingChecklist,
      budgetBreakdown: budgetBreakdown,
      conciergeNotes: conciergeNotes,
      createdAt: DateTime.now(),
      engineLabel: engineLabel,
    );

    await storageService.saveTrip(trip);
    return trip;
  }
}
