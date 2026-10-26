import 'budget_breakdown.dart';

/// Persisted travel dossier synthesized by the 3-agent Pocket Squad pipeline.
class SavedTrip {
  const SavedTrip({
    required this.id,
    required this.destination,
    required this.days,
    required this.itinerarySummary,
    required this.packingChecklist,
    required this.budgetBreakdown,
    required this.conciergeNotes,
    required this.createdAt,
    required this.engineLabel,
  });

  final String id;
  final String destination;
  final int days;
  final String itinerarySummary;
  final List<String> packingChecklist;
  final BudgetBreakdown budgetBreakdown;
  final String conciergeNotes;
  final DateTime createdAt;
  final String engineLabel;

  SavedTrip copyWith({
    String? id,
    String? destination,
    int? days,
    String? itinerarySummary,
    List<String>? packingChecklist,
    BudgetBreakdown? budgetBreakdown,
    String? conciergeNotes,
    DateTime? createdAt,
    String? engineLabel,
  }) {
    return SavedTrip(
      id: id ?? this.id,
      destination: destination ?? this.destination,
      days: days ?? this.days,
      itinerarySummary: itinerarySummary ?? this.itinerarySummary,
      packingChecklist: packingChecklist ?? this.packingChecklist,
      budgetBreakdown: budgetBreakdown ?? this.budgetBreakdown,
      conciergeNotes: conciergeNotes ?? this.conciergeNotes,
      createdAt: createdAt ?? this.createdAt,
      engineLabel: engineLabel ?? this.engineLabel,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'destination': destination,
      'days': days,
      'itinerarySummary': itinerarySummary,
      'packingChecklist': packingChecklist,
      'budgetBreakdown': budgetBreakdown.toJson(),
      'conciergeNotes': conciergeNotes,
      'createdAt': createdAt.toIso8601String(),
      'engineLabel': engineLabel,
    };
  }

  factory SavedTrip.fromJson(Map<String, dynamic> json) {
    final rawChecklist =
        json['packingChecklist'] ??
        json['packing_checklist'] ??
        const <dynamic>[];
    final checklist = rawChecklist is List
        ? rawChecklist.map((item) => item.toString()).toList()
        : const <String>[];

    final rawBudget = json['budgetBreakdown'] ?? json['budget_breakdown'];
    final budgetMap = rawBudget is Map<String, dynamic>
        ? rawBudget
        : rawBudget is Map
        ? Map<String, dynamic>.from(rawBudget)
        : <String, dynamic>{};

    final rawCreatedAt = json['createdAt'] ?? json['created_at'];
    final parsedDate = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt) ?? DateTime.now()
        : DateTime.now();

    final rawDays = json['days'];
    final parsedDays = rawDays is int
        ? rawDays
        : rawDays is num
        ? rawDays.toInt()
        : int.tryParse(rawDays?.toString() ?? '') ??
              (budgetMap['days'] is num
                  ? (budgetMap['days'] as num).toInt()
                  : 3);

    return SavedTrip(
      id:
          (json['id'] as String?) ??
          'trip-${DateTime.now().millisecondsSinceEpoch}',
      destination: (json['destination'] as String?) ?? 'Unknown Destination',
      days: parsedDays,
      itinerarySummary:
          (json['itinerarySummary'] as String?) ??
          (json['itinerary_summary'] as String?) ??
          '',
      packingChecklist: checklist,
      budgetBreakdown: BudgetBreakdown.fromJson(budgetMap),
      conciergeNotes:
          (json['conciergeNotes'] as String?) ??
          (json['concierge_notes'] as String?) ??
          '',
      createdAt: parsedDate,
      engineLabel:
          (json['engineLabel'] as String?) ??
          (json['engine_label'] as String?) ??
          'On-Device Gemma 4 E2B (LiteRT-LM)',
    );
  }
}
