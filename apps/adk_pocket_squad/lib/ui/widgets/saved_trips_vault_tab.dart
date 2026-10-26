import 'package:flutter/material.dart';

import '../../domain/models/saved_trip.dart';
import '../theme/pocket_squad_theme.dart';
import 'formatted_agent_message_view.dart';

/// Tab 3: Saved Trips Vault.
///
/// Displays persisted [SavedTrip] dossiers created by `ConciergeAgent`'s
/// `save_trip_plan` `FunctionTool`, including itemized USD & foreign currency
/// breakdowns, budget compliance pills, formatted concierge briefs, and a
/// full-screen **View Final Result & Full Itinerary** modal sheet.
class SavedTripsVaultTab extends StatelessWidget {
  const SavedTripsVaultTab({
    super.key,
    required this.savedTrips,
    required this.onDeleteTrip,
    this.onLaunchSampleMission,
  });

  final List<SavedTrip> savedTrips;
  final ValueChanged<String> onDeleteTrip;
  final VoidCallback? onLaunchSampleMission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (savedTrips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.luggage_outlined,
                  size: 42,
                  color: PocketSquadTheme.sunsetAmber,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No Saved Trips in Vault Yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Launch a destination mission in the Squad Mission tab. '
                'ConciergeAgent automatically invokes save_trip_plan to store '
                'your audited itinerary, budget breakdown, and final brief here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (onLaunchSampleMission != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onLaunchSampleMission,
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Go to Squad Mission'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: savedTrips.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final trip = savedTrips[index];
        return _SavedTripDossierCard(
          key: Key('saved_trip_card_${trip.id}'),
          trip: trip,
          onDelete: () => onDeleteTrip(trip.id),
        );
      },
    );
  }
}

class _SavedTripDossierCard extends StatelessWidget {
  const _SavedTripDossierCard({
    super.key,
    required this.trip,
    required this.onDelete,
  });

  final SavedTrip trip;
  final VoidCallback onDelete;

  Future<void> _showTripFinalResultSheet(
    BuildContext context,
    SavedTrip trip,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PocketSquadTheme.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _TripFinalResultSheet(trip: trip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = trip.budgetBreakdown;
    final statusColor = budget.withinBudget
        ? PocketSquadTheme.emeraldAudit
        : PocketSquadTheme.roseOverBudget;
    final statusText = budget.withinBudget ? 'WITHIN BUDGET' : 'OVER BUDGET';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.flight_land_rounded,
                    color: PocketSquadTheme.sunsetAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        trip.destination,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          _buildBadge(
                            theme,
                            label: '${trip.days} Days',
                            color: PocketSquadTheme.compassCyan,
                          ),
                          _buildBadge(
                            theme,
                            label: statusText,
                            color: statusColor,
                          ),
                          _buildBadge(
                            theme,
                            label: trip.engineLabel,
                            color: PocketSquadTheme.tropicalTeal,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('delete_trip_${trip.id}'),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete Saved Trip',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                key: Key('view_final_result_${trip.id}'),
                onPressed: () => _showTripFinalResultSheet(context, trip),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('View Final Result & Full Itinerary'),
              ),
            ),
            const SizedBox(height: 12),
            _buildBudgetSummaryBox(theme, trip),
            if (trip.conciergeNotes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 15,
                    color: PocketSquadTheme.sunsetAmber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Final Concierge Result Preview',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: PocketSquadTheme.sunsetAmberSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PocketSquadTheme.obsidianDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PocketSquadTheme.obsidianBorder),
                ),
                child: FormattedAgentMessageView(
                  text: trip.conciergeNotes,
                  accentColor: PocketSquadTheme.conciergeAgentColor,
                  maxBlocks: 4,
                ),
              ),
            ],
            if (trip.itinerarySummary.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.explore_outlined,
                    size: 15,
                    color: PocketSquadTheme.compassCyan,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Route & Neighborhood Highlights',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: PocketSquadTheme.compassCyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PocketSquadTheme.obsidianDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PocketSquadTheme.obsidianBorder),
                ),
                child: FormattedAgentMessageView(
                  text: trip.itinerarySummary,
                  accentColor: PocketSquadTheme.scoutAgentColor,
                  maxBlocks: 4,
                ),
              ),
            ],
            if (trip.packingChecklist.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Packing Checklist',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: trip.packingChecklist.map((item) {
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: const Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: PocketSquadTheme.sunsetAmber,
                    ),
                    label: Text(item, style: const TextStyle(fontSize: 11)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildBudgetSummaryBox(ThemeData theme, SavedTrip trip) {
    final budget = trip.budgetBreakdown;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PocketSquadTheme.obsidianDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PocketSquadTheme.obsidianBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'Deterministic Budget Audit',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PocketSquadTheme.emeraldAudit,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Target Budget: \$${budget.userBudgetUsd.toStringAsFixed(2)} USD',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildBudgetRow(
            theme,
            'Lodging (${budget.days}n × \$${budget.lodgingPerNightUsd.toStringAsFixed(0)})',
            '\$${budget.lodgingTotalUsd.toStringAsFixed(2)}',
          ),
          _buildBudgetRow(
            theme,
            'Food & Dining (${budget.days}d × \$${budget.foodPerDayUsd.toStringAsFixed(0)})',
            '\$${budget.foodTotalUsd.toStringAsFixed(2)}',
          ),
          _buildBudgetRow(
            theme,
            'Activities & Transit',
            '\$${budget.activitiesTotalUsd.toStringAsFixed(2)}',
          ),
          _buildBudgetRow(
            theme,
            '10% Contingency Buffer',
            '\$${budget.contingencyBufferUsd.toStringAsFixed(2)}',
          ),
          const Divider(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  'Grand Total (USD / ${budget.targetCurrency})',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '\$${budget.grandTotalUsd.toStringAsFixed(2)} USD · '
                  '${budget.convertedGrandTotal.toStringAsFixed(0)} ${budget.targetCurrency}',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PocketSquadTheme.sunsetAmberSoft,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildBadge(
    ThemeData theme, {
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  static Widget _buildBudgetRow(ThemeData theme, String label, String amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripFinalResultSheet extends StatelessWidget {
  const _TripFinalResultSheet({required this.trip});

  final SavedTrip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = trip.budgetBreakdown;
    final statusColor = budget.withinBudget
        ? PocketSquadTheme.emeraldAudit
        : PocketSquadTheme.roseOverBudget;
    final statusText = budget.withinBudget ? 'WITHIN BUDGET' : 'OVER BUDGET';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PocketSquadTheme.sunsetAmber.withValues(
                        alpha: 0.16,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.luggage_rounded,
                      color: PocketSquadTheme.sunsetAmber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${trip.destination} — Final Result Dossier',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${trip.days} Days · $statusText · ${trip.engineLabel}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('close_final_result_sheet_button'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildDossierSectionCard(
                      theme: theme,
                      title: '3 · Executive Concierge Final Result',
                      subtitle:
                          'Synthesized by ConciergeAgent (save_trip_plan)',
                      icon: Icons.luggage_outlined,
                      accentColor: PocketSquadTheme.conciergeAgentColor,
                      content: trip.conciergeNotes.trim().isNotEmpty
                          ? trip.conciergeNotes
                          : 'Saved executive dossier for ${trip.destination}.',
                    ),
                    const SizedBox(height: 12),
                    _buildDossierSectionCard(
                      theme: theme,
                      title: '1 · Complete Day-by-Day Route & Neighborhoods',
                      subtitle:
                          'Designed by ScoutAgent (100% Native LLM Knowledge)',
                      icon: Icons.explore_outlined,
                      accentColor: PocketSquadTheme.scoutAgentColor,
                      content: trip.itinerarySummary.trim().isNotEmpty
                          ? trip.itinerarySummary
                          : '${trip.days}-day curated cultural and culinary route across ${trip.destination}.',
                    ),
                    const SizedBox(height: 12),
                    _SavedTripDossierCard._buildBudgetSummaryBox(theme, trip),
                    if (trip.packingChecklist.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(
                        'Essential Packing Checklist',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: trip.packingChecklist.map((item) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(
                              Icons.check_circle_outline,
                              size: 14,
                              color: PocketSquadTheme.sunsetAmber,
                            ),
                            label: Text(
                              item,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDossierSectionCard({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PocketSquadTheme.obsidianDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 17, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          FormattedAgentMessageView(text: content, accentColor: accentColor),
        ],
      ),
    );
  }
}
