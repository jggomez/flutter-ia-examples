import 'package:flutter/material.dart';

import 'flutter_adk_widgets.dart';

import '../../domain/models/budget_breakdown.dart';
import '../theme/pocket_squad_theme.dart';

/// Compact live 4-step multi-agent pipeline banner (`0. Coordinator` →
/// `1. ScoutAgent` → `2. BudgetAuditor` → `3. Concierge`) displaying
/// [AdkAgentHierarchyBadge], [AdkWorkflowProgressIndicator], and the latest
/// deterministic budget pill.
class SquadPipelineHeader extends StatelessWidget {
  const SquadPipelineHeader({
    super.key,
    required this.activeAgentHierarchy,
    required this.workflowSteps,
    this.latestBudget,
    this.isBusy = false,
    this.onResetSession,
  });

  final List<String> activeAgentHierarchy;
  final List<AdkWorkflowStep> workflowSteps;
  final BudgetBreakdown? latestBudget;
  final bool isBusy;
  final VoidCallback? onResetSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budget = latestBudget;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PocketSquadTheme.obsidianSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PocketSquadTheme.obsidianBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: AdkAgentHierarchyBadge(
                    agentPath: activeAgentHierarchy,
                    backgroundColor: PocketSquadTheme.obsidianElevated,
                    textColor: PocketSquadTheme.sunsetAmberSoft,
                  ),
                ),
              ),
              if (budget != null) ...<Widget>[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (budget.withinBudget
                                ? PocketSquadTheme.emeraldAudit
                                : PocketSquadTheme.roseOverBudget)
                            .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color:
                          (budget.withinBudget
                                  ? PocketSquadTheme.emeraldAudit
                                  : PocketSquadTheme.roseOverBudget)
                              .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '\$${budget.grandTotalUsd.toStringAsFixed(0)} · '
                    '${budget.withinBudget ? 'WITHIN BUDGET' : 'OVER BUDGET'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: budget.withinBudget
                          ? PocketSquadTheme.emeraldAudit
                          : PocketSquadTheme.roseOverBudget,
                    ),
                  ),
                ),
              ],
              if (onResetSession != null) ...<Widget>[
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  tooltip: 'Reset Squad Session',
                  onPressed: isBusy ? null : onResetSession,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          AdkWorkflowProgressIndicator(steps: workflowSteps, isVertical: false),
        ],
      ),
    );
  }
}
