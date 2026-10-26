import 'package:flutter/material.dart';

import '../theme/pocket_squad_theme.dart';
import 'flutter_adk_widgets.dart';
import 'formatted_agent_message_view.dart';

/// Tab 2: Live Pipeline & State Inspector.
///
/// Renders:
/// 1. Visual `CoordinatorAgent` → `SequentialAgent` DAG using [AdkWorkflowGraphView]
/// 2. Executed Tool Calls & Handoffs (`transfer_to_agent`, `calculate_budget_math`, `save_trip_plan`)
/// 3. Live `session.state` artifact cards (`itinerary_draft`, `budget_audit`, `final_concierge_brief`)
/// 4. Registered `FunctionTool` schemas via [AdkToolInspectorView].
class PipelineInspectorTab extends StatelessWidget {
  const PipelineInspectorTab({
    super.key,
    required this.workflowSteps,
    required this.sessionArtifacts,
    required this.registeredTools,
    this.toolCallMessages = const <AdkChatMessage>[],
    this.activeAgentName,
    this.onRefreshState,
  });

  final List<AdkWorkflowStep> workflowSteps;
  final Map<String, String> sessionArtifacts;
  final List<Object> registeredTools;
  final List<AdkChatMessage> toolCallMessages;
  final String? activeAgentName;
  final VoidCallback? onRefreshState;

  AdkGraphNodeStatus _mapStepStatus(AdkStepStatus status) {
    return switch (status) {
      AdkStepStatus.pending => AdkGraphNodeStatus.pending,
      AdkStepStatus.running => AdkGraphNodeStatus.running,
      AdkStepStatus.completed => AdkGraphNodeStatus.completed,
      AdkStepStatus.failed => AdkGraphNodeStatus.failed,
      AdkStepStatus.skipped => AdkGraphNodeStatus.skipped,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final nodes = workflowSteps.map((step) {
      final subtitle = switch (step.id) {
        'coordinator_agent' => 'LlmAgent · Intake + transfer_to_agent',
        'scout_agent' => '0 Tools · Native LLM',
        'budget_auditor_agent' => 'Tool: calculate_budget_math',
        'concierge_agent' => 'Tool: save_trip_plan',
        _ => step.description,
      };
      return AdkGraphNode(
        id: step.id,
        label: step.label,
        subtitle: subtitle,
        status: _mapStepStatus(step.status),
        icon: PocketSquadTheme.agentIcon(step.id),
      );
    }).toList();

    const edges = <AdkGraphEdge>[
      AdkGraphEdge(
        fromId: 'coordinator_agent',
        toId: 'scout_agent',
        label: 'transfer_to_agent',
      ),
      AdkGraphEdge(
        fromId: 'scout_agent',
        toId: 'budget_auditor_agent',
        label: 'itinerary_draft',
      ),
      AdkGraphEdge(
        fromId: 'budget_auditor_agent',
        toId: 'concierge_agent',
        label: 'budget_audit',
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.account_tree_rounded,
                        size: 16,
                        color: PocketSquadTheme.coordinatorViolet,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hierarchical Multi-Agent Architecture',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: PocketSquadTheme.coordinatorViolet,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'CoordinatorAgent (LlmAgent conversational intake + transfer_to_agent) '
                    '→ SequentialAgent (ScoutAgent → BudgetAuditorAgent → ConciergeAgent).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AdkWorkflowGraphView(
            title: 'Coordinator → Squad Pipeline',
            nodes: nodes,
            edges: edges,
            activeNodeId: activeAgentName,
            orientation: Axis.horizontal,
            nodeWidth: 165,
            cardMargin: EdgeInsets.zero,
            completedColor: PocketSquadTheme.emeraldAudit,
            runningColor: PocketSquadTheme.sunsetAmber,
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Icon(
                Icons.swap_horiz_rounded,
                size: 18,
                color: PocketSquadTheme.coordinatorViolet,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Executed Tool Calls & Handoffs (${toolCallMessages.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (toolCallMessages.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No tool calls executed in this session yet. Once CoordinatorAgent has '
                  'Destination, Days & Budget, it invokes transfer_to_agent, followed by '
                  'calculate_budget_math and save_trip_plan.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            ...toolCallMessages.map((msg) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdkToolCallCard(
                  toolName: msg.toolName ?? 'tool_call',
                  toolArgs: msg.toolArgs,
                  toolResult: msg.toolResult,
                  isRunning: msg.isPartial,
                  errorMessage: msg.errorMessage,
                  initiallyExpanded: false,
                ),
              );
            }),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.data_object_rounded,
                    size: 18,
                    color: PocketSquadTheme.sunsetAmber,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Shared Session State (session.state)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (onRefreshState != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  tooltip: 'Sync session.state',
                  onPressed: onRefreshState,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStateArtifactCard(
            context: context,
            stateKey: 'itinerary_draft',
            producerAgent: 'scout_agent',
            description: 'Generated by ScoutAgent (100% Native LLM Knowledge)',
            value: sessionArtifacts['itinerary_draft'] ?? '',
            accentColor: PocketSquadTheme.scoutAgentColor,
          ),
          const SizedBox(height: 10),
          _buildStateArtifactCard(
            context: context,
            stateKey: 'budget_audit',
            producerAgent: 'budget_auditor_agent',
            description: 'Generated by BudgetAuditorAgent + calculate_budget_math FunctionTool',
            value: sessionArtifacts['budget_audit'] ?? '',
            accentColor: PocketSquadTheme.budgetAuditorAgentColor,
          ),
          const SizedBox(height: 10),
          _buildStateArtifactCard(
            context: context,
            stateKey: 'final_concierge_brief',
            producerAgent: 'concierge_agent',
            description:
                'Generated by ConciergeAgent + save_trip_plan FunctionTool',
            value: sessionArtifacts['final_concierge_brief'] ?? '',
            accentColor: PocketSquadTheme.conciergeAgentColor,
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Icon(
                Icons.build_circle_outlined,
                size: 18,
                color: PocketSquadTheme.tropicalTeal,
              ),
              const SizedBox(width: 8),
              Text(
                'Registered ADK FunctionTools (${registeredTools.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: AdkToolInspectorView(
              tools: registeredTools,
              title: 'Squad FunctionTools',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateArtifactCard({
    required BuildContext context,
    required String stateKey,
    required String producerAgent,
    required String description,
    required String value,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final cleanedValue = FormattedAgentMessageView.cleanRawAgentHeaders(value);
    final hasValue = cleanedValue.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    stateKey,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    producerAgent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  hasValue ? Icons.check_circle : Icons.hourglass_empty,
                  size: 16,
                  color: hasValue
                      ? PocketSquadTheme.emeraldAudit
                      : theme.colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PocketSquadTheme.obsidianDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PocketSquadTheme.obsidianBorder),
              ),
              child: hasValue
                  ? FormattedAgentMessageView(
                      text: value,
                      accentColor: accentColor,
                    )
                  : Text(
                      'Awaiting pipeline execution for {$stateKey}...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
