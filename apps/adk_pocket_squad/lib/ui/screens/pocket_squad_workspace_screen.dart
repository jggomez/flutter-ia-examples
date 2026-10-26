import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/squad_mission_preset.dart';
import '../providers/app_providers.dart';
import '../theme/pocket_squad_theme.dart';
import '../view_models/pocket_squad_view_model.dart';
import '../widgets/engine_mode_sheet.dart';
import '../widgets/flutter_adk_widgets.dart';
import '../widgets/formatted_agent_message_view.dart';
import '../widgets/mission_preset_carousel.dart';
import '../widgets/pipeline_inspector_tab.dart';
import '../widgets/pocket_squad_adk_studio_tab.dart';
import '../widgets/saved_trips_vault_tab.dart';
import '../widgets/squad_pipeline_header.dart';

/// Primary 4-tab workspace for **Pocket Squad: Editorial Luxury Travel & Budget Concierge**.
class PocketSquadWorkspaceScreen extends ConsumerStatefulWidget {
  const PocketSquadWorkspaceScreen({super.key});

  @override
  ConsumerState<PocketSquadWorkspaceScreen> createState() =>
      _PocketSquadWorkspaceScreenState();
}

class _PocketSquadWorkspaceScreenState
    extends ConsumerState<PocketSquadWorkspaceScreen> {
  int _selectedTabIndex = 0;

  Future<void> _openEngineSettings(PocketSquadViewModel viewModel) async {
    await viewModel.refreshWifiStatus();
    if (!mounted) return;
    await EngineModeSheet.show(
      context,
      initialConfig: viewModel.engineConfig,
      isOnWifi: viewModel.isOnWifi,
      onApply: viewModel.updateEngineConfig,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = ref.watch(pocketSquadViewModelProvider);

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final theme = Theme.of(context);
        final isWifi = viewModel.isOnWifi;
        final engineShort = viewModel.engineConfig.isOnDevice
            ? 'On-Device Gemma 4 E2B'
            : 'LAN Ollama';

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.luggage_rounded,
                    color: PocketSquadTheme.sunsetAmber,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Pocket Squad',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PocketSquadTheme.obsidianElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PocketSquadTheme.obsidianBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isWifi
                            ? PocketSquadTheme.emeraldAudit
                            : PocketSquadTheme.sunsetAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      engineShort,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: PocketSquadTheme.sunsetAmberSoft,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('engine_mode_settings_button'),
                icon: const Icon(Icons.tune_rounded, size: 20),
                tooltip: 'Engine & Runtime Settings',
                onPressed: () => _openEngineSettings(viewModel),
              ),
            ],
          ),
          body: _buildActiveTab(context, viewModel, theme),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedTabIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedTabIndex = index);
              if (index == 1) {
                viewModel.syncSessionState();
              } else if (index == 2) {
                viewModel.refreshSavedTrips();
              }
            },
            destinations: <Widget>[
              const NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore_rounded),
                label: 'Squad Mission',
              ),
              const NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree_rounded),
                label: 'Pipeline & State',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: viewModel.savedTrips.isNotEmpty,
                  label: Text('${viewModel.savedTrips.length}'),
                  child: const Icon(Icons.luggage_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: viewModel.savedTrips.isNotEmpty,
                  label: Text('${viewModel.savedTrips.length}'),
                  child: const Icon(Icons.luggage_rounded),
                ),
                label: 'Trips Vault',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: viewModel.agentLogs.isNotEmpty,
                  label: Text('${viewModel.agentLogs.length}'),
                  child: const Icon(Icons.developer_board_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: viewModel.agentLogs.isNotEmpty,
                  label: Text('${viewModel.agentLogs.length}'),
                  child: const Icon(Icons.developer_board_rounded),
                ),
                label: 'ADK Studio',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTab(
    BuildContext context,
    PocketSquadViewModel viewModel,
    ThemeData theme,
  ) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildMissionChatTab(context, viewModel, theme);
      case 1:
        return PipelineInspectorTab(
          workflowSteps: viewModel.workflowSteps,
          sessionArtifacts: viewModel.sessionArtifacts,
          registeredTools: viewModel.registeredTools,
          toolCallMessages: viewModel.toolCallMessages,
          activeAgentName: viewModel.activeAgentName,
          onRefreshState: viewModel.syncSessionState,
        );
      case 2:
        return SavedTripsVaultTab(
          savedTrips: viewModel.savedTrips,
          onDeleteTrip: viewModel.deleteSavedTrip,
          onLaunchSampleMission: () {
            setState(() => _selectedTabIndex = 0);
          },
        );
      case 3:
        return PocketSquadAdkStudioTab(viewModel: viewModel);
      default:
        return _buildMissionChatTab(context, viewModel, theme);
    }
  }

  Widget _buildMissionChatTab(
    BuildContext context,
    PocketSquadViewModel viewModel,
    ThemeData theme,
  ) {
    final hasConversationStarted = viewModel.chatController.messages.isNotEmpty;

    return Column(
      children: <Widget>[
        SquadPipelineHeader(
          activeAgentHierarchy: viewModel.activeAgentHierarchy,
          workflowSteps: viewModel.workflowSteps,
          latestBudget: viewModel.latestBudget,
          isBusy: viewModel.isBusy,
          onResetSession: viewModel.resetMissionSession,
        ),
        if (!hasConversationStarted)
          MissionPresetCarousel(
            presets: SquadMissionPreset.defaultPresets,
            enabled: !viewModel.isBusy,
            onSelectPreset: (preset) {
              viewModel.runPresetMission(preset);
            },
          ),
        Expanded(
          child: AdkChatView(
            controller: viewModel.chatController,
            theme: PocketSquadTheme.adkChatTheme(theme),
            title: 'Coordinator + 3-Agent Travel Concierge',
            inputPlaceholder: "Say 'Hola' or ask to plan a trip (Destination, Days & Budget)...",
            suggestions: null,
            emptyStateBuilder: (context) => _buildChatEmptyState(theme),
            messageBubbleBuilder: (context, message) =>
                _buildCustomMessageBubble(
                  context,
                  theme,
                  viewModel.chatController.messages,
                  message,
                ),
            inputBarBuilder: (context, textController, defaultSend, isLoading) {
              return _buildMissionInputBar(
                theme: theme,
                textController: textController,
                isBusy: viewModel.isBusy || isLoading,
                onSubmit: () {
                  final text = textController.text.trim();
                  if (text.isEmpty || viewModel.isBusy) return;
                  textController.clear();
                  viewModel.runMissionPrompt(text);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.public_rounded,
                size: 32,
                color: PocketSquadTheme.sunsetAmber,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Editorial Travel & Budget Concierge',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Say 'Hola' to chat with CoordinatorAgent or tap a curated preset above. "
              'Once Destination, Days & Budget are collected, CoordinatorAgent transfers '
              'to ScoutAgent, BudgetAuditorAgent (calculate_budget_math), and ConciergeAgent (save_trip_plan).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AdkChatMessage? _resolveTurnModelMessageForSlot(
    List<AdkChatMessage> allMessages,
    AdkChatMessage message,
  ) {
    final index = allMessages.indexWhere((m) => m.id == message.id);
    if (index == -1) {
      return (message.isTool || message.role == AdkMessageRole.tool)
          ? null
          : message;
    }

    var turnStart = index;
    while (turnStart > 0 && !allMessages[turnStart - 1].isUser) {
      turnStart--;
    }
    var turnEnd = index;
    while (turnEnd + 1 < allMessages.length &&
        !allMessages[turnEnd + 1].isUser) {
      turnEnd++;
    }

    if (index != turnEnd) {
      return null;
    }

    for (var i = turnEnd; i >= turnStart; i--) {
      final candidate = allMessages[i];
      if (!candidate.isUser &&
          !candidate.isTool &&
          candidate.role != AdkMessageRole.tool) {
        return candidate;
      }
    }
    return null;
  }

  Widget _buildCustomMessageBubble(
    BuildContext context,
    ThemeData theme,
    List<AdkChatMessage> allMessages,
    AdkChatMessage message,
  ) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: PocketSquadTheme.sunsetAmber,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Color(0xFF140D00),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    // Requirement 2: Do NOT show tool calls inside Squad Mission chat;
    // render the turn's model response cards in the final slot of the turn slice.
    final resolvedModelMessage = _resolveTurnModelMessageForSlot(
      allMessages,
      message,
    );
    if (resolvedModelMessage == null) {
      return const SizedBox.shrink();
    }

    final sections = FormattedAgentMessageView.splitAgentSections(
      resolvedModelMessage.text,
      fallbackAuthor: resolvedModelMessage.author,
    );
    if (sections.isEmpty && resolvedModelMessage.errorMessage == null) {
      return const SizedBox.shrink();
    }

    if (sections.isEmpty) {
      return _buildSingleAgentCard(
        theme: theme,
        author: resolvedModelMessage.author,
        content: '',
        isPartial: resolvedModelMessage.isPartial,
        errorMessage: resolvedModelMessage.errorMessage,
      );
    }

    if (sections.length == 1) {
      final single = sections.first;
      return _buildSingleAgentCard(
        theme: theme,
        author: single.author,
        content: single.content,
        isPartial: resolvedModelMessage.isPartial,
        errorMessage: resolvedModelMessage.errorMessage,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < sections.length; i++)
          _buildSingleAgentCard(
            theme: theme,
            author: sections[i].author,
            content: sections[i].content,
            isPartial:
                resolvedModelMessage.isPartial && i == sections.length - 1,
            errorMessage: i == sections.length - 1
                ? resolvedModelMessage.errorMessage
                : null,
          ),
      ],
    );
  }

  Widget _buildSingleAgentCard({
    required ThemeData theme,
    required String author,
    required String content,
    required bool isPartial,
    String? errorMessage,
  }) {
    final accentColor = PocketSquadTheme.agentColor(author);
    final roleTitle = PocketSquadTheme.agentBadgeLabel(author);
    final roleIcon = PocketSquadTheme.agentIcon(author);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PocketSquadTheme.obsidianSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(roleIcon, size: 13, color: accentColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          roleTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isPartial) ...<Widget>[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: accentColor,
                  ),
                ),
              ],
            ],
          ),
          if (content.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            FormattedAgentMessageView(text: content, accentColor: accentColor),
          ],
          if (errorMessage != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: PocketSquadTheme.roseOverBudget,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMissionInputBar({
    required ThemeData theme,
    required TextEditingController textController,
    required bool isBusy,
    required VoidCallback onSubmit,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      color: PocketSquadTheme.obsidianDeep,
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: const Key('mission_prompt_text_field'),
              controller: textController,
              enabled: !isBusy,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                hintText: "Say 'Hola' or ask to plan a trip (Destination, Days & Budget)...",
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            key: const Key('send_mission_prompt_button'),
            onPressed: isBusy ? null : onSubmit,
            style: IconButton.styleFrom(
              backgroundColor: PocketSquadTheme.sunsetAmber,
              foregroundColor: const Color(0xFF140D00),
            ),
            icon: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
