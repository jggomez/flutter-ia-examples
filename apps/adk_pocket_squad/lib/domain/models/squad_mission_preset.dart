/// Curated quick-launch mission card preset for the Travel & Budget Concierge.
class SquadMissionPreset {
  const SquadMissionPreset({
    required this.id,
    required this.title,
    required this.destination,
    required this.days,
    required this.budgetUsd,
    required this.currency,
    required this.vibeTag,
    required this.prompt,
    required this.accentHex,
  });

  final String id;
  final String title;
  final String destination;
  final int days;
  final double budgetUsd;
  final String currency;
  final String vibeTag;
  final String prompt;
  final int accentHex;

  /// Four curated global travel missions showcasing authentic LLM knowledge,
  /// multi-currency budget auditing, and persistent vault storage.
  static const List<SquadMissionPreset> defaultPresets = <SquadMissionPreset>[
    SquadMissionPreset(
      id: 'kyoto_cultural_odyssey',
      title: 'Kyoto Cultural Odyssey',
      destination: 'Kyoto, Japan',
      days: 4,
      budgetUsd: 1200,
      currency: 'JPY',
      vibeTag: 'Temples • Tea Houses • Bamboo Groves',
      prompt: 'Plan a 4-day Kyoto Cultural Odyssey in Kyoto, Japan with a total budget of \$1,200 USD (convert to JPY). Include Higashiyama, Arashiyama, Fushimi Inari, realistic nightly ryokan/hotel and kaiseki/street food costs, audit the budget, and save the trip plan.',
      accentHex: 0xFF06B6D4,
    ),
    SquadMissionPreset(
      id: 'cartagena_caribbean_escape',
      title: 'Cartagena Caribbean Escape',
      destination: 'Cartagena, Colombia',
      days: 3,
      budgetUsd: 750,
      currency: 'COP',
      vibeTag: 'Walled City • Rosario Islands • Ceviche',
      prompt: 'Plan a 3-day Cartagena Caribbean Escape in Cartagena, Colombia with a total budget of \$750 USD (convert to COP). Cover Centro Histórico, Getsemaní street art, and a Rosario Islands boat day, audit the budget, and save the trip plan.',
      accentHex: 0xFFF59E0B,
    ),
    SquadMissionPreset(
      id: 'lisbon_culinary_tram_tour',
      title: 'Lisbon Culinary & Tram Tour',
      destination: 'Lisbon, Portugal',
      days: 5,
      budgetUsd: 1500,
      currency: 'EUR',
      vibeTag: 'Alfama • Pastéis • Miradouros',
      prompt: 'Plan a 5-day Lisbon Culinary & Tram Tour in Lisbon, Portugal with a total budget of \$1,500 USD (convert to EUR). Include Alfama, Belém, Bairro Alto, and a Sintra day trip with realistic lodging and dining estimates, audit the budget, and save the trip plan.',
      accentHex: 0xFF10B981,
    ),
    SquadMissionPreset(
      id: 'reykjavik_northern_lights',
      title: 'Reykjavik Northern Lights',
      destination: 'Reykjavik, Iceland',
      days: 4,
      budgetUsd: 1800,
      currency: 'EUR',
      vibeTag: 'Auroras • Geothermal Lagoons • Golden Circle',
      prompt: 'Plan a 4-day Reykjavik Northern Lights adventure in Reykjavik, Iceland with a total budget of \$1,800 USD (convert to EUR). Include downtown Reykjavik, Sky Lagoon, the Golden Circle, and South Coast glaciers, audit the budget, and save the trip plan.',
      accentHex: 0xFF8B5CF6,
    ),
  ];

  /// Alias for [defaultPresets] for convenient access across UI components.
  static const List<SquadMissionPreset> presets = defaultPresets;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'destination': destination,
      'days': days,
      'budgetUsd': budgetUsd,
      'currency': currency,
      'vibeTag': vibeTag,
      'prompt': prompt,
      'accentHex': accentHex,
    };
  }

  factory SquadMissionPreset.fromJson(Map<String, dynamic> json) {
    return SquadMissionPreset(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      destination: (json['destination'] as String?) ?? '',
      days: (json['days'] as num?)?.toInt() ?? 3,
      budgetUsd: (json['budgetUsd'] as num?)?.toDouble() ?? 1000.0,
      currency: (json['currency'] as String?) ?? 'USD',
      vibeTag: (json['vibeTag'] as String?) ?? '',
      prompt: (json['prompt'] as String?) ?? '',
      accentHex: (json['accentHex'] as int?) ?? 0xFFF59E0B,
    );
  }
}
