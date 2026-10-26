import 'package:flutter/material.dart';

import '../theme/pocket_squad_theme.dart';
import '../view_models/pocket_squad_view_model.dart';
import 'flutter_adk_widgets.dart';
import 'formatted_agent_message_view.dart';

/// Tab 4: Persistent ADK Studio with Live Logger as the default tab.
///
/// Unlike the ephemeral internal state of stock [AdkDevStudioView], this
/// studio binds directly to [PocketSquadViewModel.agentLogs],
/// [PocketSquadViewModel.toolCallMessages], and [PocketSquadViewModel.sessionArtifacts]
/// so every event from **Squad Mission** is immediately visible in **Live Logger**.
class PocketSquadAdkStudioTab extends StatelessWidget {
  const PocketSquadAdkStudioTab({super.key, required this.viewModel});

  final PocketSquadViewModel viewModel;

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
    final logCount = viewModel.agentLogs.length;
    final toolCount = viewModel.toolCallMessages.length;

    return DefaultTabController(
      length: 4,
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            decoration: const BoxDecoration(
              color: PocketSquadTheme.obsidianSurface,
              border: Border(
                bottom: BorderSide(color: PocketSquadTheme.obsidianBorder),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.developer_board_rounded,
                      size: 18,
                      color: PocketSquadTheme.sunsetAmber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pocket Squad ADK Studio',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: PocketSquadTheme.coordinatorViolet.withValues(
                          alpha: 0.16,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: PocketSquadTheme.coordinatorViolet.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Text(
                        '$logCount Logs · $toolCount Tool Events',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: PocketSquadTheme.coordinatorViolet,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: <Widget>[
                    Tab(
                      icon: Icon(Icons.terminal_rounded, size: 16),
                      text: 'Live Logger',
                    ),
                    Tab(
                      icon: Icon(Icons.hub_outlined, size: 16),
                      text: 'Agent Graph',
                    ),
                    Tab(
                      icon: Icon(Icons.data_object_rounded, size: 16),
                      text: 'State & Tools',
                    ),
                    Tab(
                      icon: Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      text: 'Playground',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                // Sub-tab 0: Persistent Live Logger
                AdkAgentLoggerView(
                  logs: viewModel.agentLogs,
                  onClearLogs: viewModel.clearAgentLogs,
                  title:
                      'Live Agent & Tool Telemetry (${viewModel.agentLogs.length})',
                ),

                // Sub-tab 1: Agent Graph & Hierarchy
                _buildAgentGraphSubTab(theme),

                // Sub-tab 2: Session State & Executed Tools
                _buildStateAndToolsSubTab(theme),

                // Sub-tab 3: Interactive Developer Playground
                AdkChatView(
                  controller: viewModel.chatController,
                  theme: PocketSquadTheme.adkChatTheme(theme),
                  title: 'ADK Developer Playground',
                  suggestions: null,
                  messageBubbleBuilder: (context, message) {
                    if (message.isTool && message.toolName != null) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: AdkToolCallCard(
                          toolName: message.toolName!,
                          toolArgs: message.toolArgs,
                          toolResult: message.toolResult,
                          isRunning: message.isPartial,
                          errorMessage: message.errorMessage,
                          initiallyExpanded: false,
                        ),
                      );
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PocketSquadTheme.obsidianSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: PocketSquadTheme.obsidianBorder,
                        ),
                      ),
                      child: FormattedAgentMessageView(
                        text: message.text,
                        accentColor: PocketSquadTheme.agentColor(
                          message.author,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentGraphSubTab(ThemeData theme) {
    final nodes = viewModel.workflowSteps.map((step) {
      return AdkGraphNode(
        id: step.id,
        label: step.label,
        subtitle: step.description,
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AdkWorkflowGraphView(
            title: 'Coordinator → Squad Pipeline',
            nodes: nodes,
            edges: edges,
            activeNodeId: viewModel.activeAgentName,
            orientation: Axis.horizontal,
            nodeWidth: 165,
            cardMargin: EdgeInsets.zero,
            completedColor: PocketSquadTheme.emeraldAudit,
            runningColor: PocketSquadTheme.sunsetAmber,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Active Agent Hierarchy Path',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AdkAgentHierarchyBadge(
                    agentPath: viewModel.activeAgentHierarchy,
                    backgroundColor: PocketSquadTheme.obsidianElevated,
                    textColor: PocketSquadTheme.sunsetAmberSoft,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateAndToolsSubTab(ThemeData theme) {
    final artifacts = viewModel.sessionArtifacts;
    final tools = viewModel.toolCallMessages;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Executed Tool Calls (${tools.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (tools.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No tool calls recorded yet in this session.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...tools.map((msg) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AdkToolCallCard(
                  toolName: msg.toolName ?? 'tool_call',
                  toolArgs: msg.toolArgs,
                  toolResult: msg.toolResult,
                  isRunning: msg.isPartial,
                  errorMessage: msg.errorMessage,
                  initiallyExpanded: true,
                ),
              );
            }),
          const SizedBox(height: 14),
          Text(
            'Session State Artifacts',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...artifacts.entries.map((entry) {
            final cleaned = FormattedAgentMessageView.cleanRawAgentHeaders(
              entry.value,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.key,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: PocketSquadTheme.sunsetAmberSoft,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (cleaned.isEmpty)
                        Text(
                          'Empty',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        FormattedAgentMessageView(
                          text: entry.value,
                          accentColor: PocketSquadTheme.sunsetAmber,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
