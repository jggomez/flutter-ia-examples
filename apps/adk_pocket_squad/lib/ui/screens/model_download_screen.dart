import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/model_download_state.dart';
import '../providers/app_providers.dart';
import '../theme/pocket_squad_theme.dart';
import '../view_models/model_download_view_model.dart';
import '../widgets/engine_mode_sheet.dart';

/// Luxury onboarding gate that verifies native Wi-Fi connectivity via
/// `MethodChannel`, checks for an existing on-device `gemma-4-E2B-it.litertlm`
/// (2.58 GB) artifact, and streams atomic `.part` download progress.
class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  final TextEditingController _hfTokenController = TextEditingController();
  bool _showTokenField = false;

  @override
  void initState() {
    super.initState();
    final vm = ref.read(modelDownloadViewModelProvider);
    if (vm.hfToken != null) {
      _hfTokenController.text = vm.hfToken!;
    }
  }

  @override
  void dispose() {
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _openEngineModeSheet(ModelDownloadViewModel viewModel) async {
    await EngineModeSheet.show(
      context,
      initialConfig: viewModel.engineConfig,
      isOnWifi: viewModel.state.isOnWifi,
      onApply: viewModel.updateEngineConfig,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = ref.watch(modelDownloadViewModelProvider);

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final state = viewModel.state;
        final theme = Theme.of(context);
        final isWifi = state.isOnWifi;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    color: PocketSquadTheme.sunsetAmber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Pocket Squad',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  key: const Key('onboarding_engine_mode_button'),
                  onPressed: () => _openEngineModeSheet(viewModel),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(viewModel.engineConfig.mode.shortLabel),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildHeroCard(theme, state, isWifi),
                      const SizedBox(height: 16),
                      _buildPipelinePreviewCard(theme),
                      const SizedBox(height: 16),
                      _buildTokenSection(theme, viewModel),
                      const SizedBox(height: 20),
                      _buildActionButtons(theme, viewModel, state),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroCard(
    ThemeData theme,
    ModelDownloadState state,
    bool isWifi,
  ) {
    final wifiColor = isWifi
        ? PocketSquadTheme.emeraldAudit
        : PocketSquadTheme.sunsetAmber;
    final wifiLabel = isWifi ? 'Wi-Fi Connected' : 'Wi-Fi Required';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '100% ON-DEVICE ADK SQUAD',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: PocketSquadTheme.sunsetAmberSoft,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                Container(
                  key: const Key('wifi_status_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: wifiColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: wifiColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        isWifi ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                        size: 14,
                        color: wifiColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        wifiLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: wifiColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Gemma 4 E2B IT (2.58 GB · LiteRT-LM CPU mmap)',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Shared singleton on-device model (~0.8 GB resident RAM via mmap) '
              'powering 3 specialized ADK agents with deterministic budget '
              'arithmetic and local Vault persistence.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _buildStatusIndicator(theme, state),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(ThemeData theme, ModelDownloadState state) {
    switch (state.phase) {
      case ModelDownloadPhase.checking:
        return const Row(
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text('Checking on-device model artifact & Wi-Fi state...'),
            ),
          ],
        );

      case ModelDownloadPhase.downloading:
        final percent = (state.progress * 100).clamp(0.0, 100.0);
        final downloadedGbText = state.downloadedGb.toStringAsFixed(2);
        final totalGbText = state.totalBytes > 0
            ? state.totalGb.toStringAsFixed(2)
            : '2.58';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Streaming atomic .part artifact...',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PocketSquadTheme.sunsetAmberSoft,
                  ),
                ),
                Text(
                  '$downloadedGbText / $totalGbText GB (${percent.toStringAsFixed(1)}%)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: state.totalBytes > 0 ? state.progress : null,
                color: PocketSquadTheme.sunsetAmber,
                backgroundColor: PocketSquadTheme.obsidianElevated,
              ),
            ),
          ],
        );

      case ModelDownloadPhase.wifiRequired:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PocketSquadTheme.sunsetAmber.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.wifi_find_rounded,
                color: PocketSquadTheme.sunsetAmber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.errorMessage ?? 'Wi-Fi Required: Connect to Wi-Fi before downloading the 2.58 GB model artifact, or switch to LAN Ollama mode.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: PocketSquadTheme.sunsetAmberSoft,
                  ),
                ),
              ),
            ],
          ),
        );

      case ModelDownloadPhase.error:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PocketSquadTheme.roseOverBudget.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: PocketSquadTheme.roseOverBudget.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                color: PocketSquadTheme.roseOverBudget,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.errorMessage ?? 'Model download failed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: PocketSquadTheme.roseOverBudget,
                  ),
                ),
              ),
            ],
          ),
        );

      case ModelDownloadPhase.notDownloaded:
      case ModelDownloadPhase.ready:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PocketSquadTheme.obsidianElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.sd_storage_outlined,
                color: PocketSquadTheme.compassCyan,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Artifact: gemma-4-E2B-it.litertlm (2.58 GB) · Ready to download over Wi-Fi.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _buildPipelinePreviewCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '3-Agent Sequential Concierge Architecture',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _buildAgentRow(
              theme,
              icon: Icons.explore_outlined,
              color: PocketSquadTheme.scoutAgentColor,
              title: '1. ScoutAgent (100% Native LLM Knowledge)',
              subtitle: 'Designs neighborhoods, routes & USD cost estimates → itinerary_draft',
            ),
            const SizedBox(height: 8),
            _buildAgentRow(
              theme,
              icon: Icons.calculate_outlined,
              color: PocketSquadTheme.budgetAuditorAgentColor,
              title: '2. BudgetAuditorAgent (calculate_budget_math Tool)',
              subtitle: 'Computes exact multi-day totals, 10% buffer & FX rates → budget_audit',
            ),
            const SizedBox(height: 8),
            _buildAgentRow(
              theme,
              icon: Icons.luggage_outlined,
              color: PocketSquadTheme.conciergeAgentColor,
              title: '3. ConciergeAgent (save_trip_plan Tool)',
              subtitle: 'Persists trip dossier to Vault & synthesizes executive brief',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentRow(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTokenSection(ThemeData theme, ModelDownloadViewModel viewModel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _showTokenField = !_showTokenField),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.vpn_key_outlined,
                    size: 18,
                    color: PocketSquadTheme.tropicalTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Optional Hugging Face Token (for gated repository access)',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _showTokenField ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showTokenField) ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                key: const Key('hf_token_text_field'),
                controller: _hfTokenController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'hf_...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.save_outlined, size: 18),
                    tooltip: 'Save Token',
                    onPressed: () {
                      viewModel.saveHfToken(_hfTokenController.text);
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    ThemeData theme,
    ModelDownloadViewModel viewModel,
    ModelDownloadState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('start_model_download_button'),
          onPressed: state.isDownloading
              ? null
              : () => viewModel.startDownload(
                  customToken: _hfTokenController.text,
                ),
          icon: const Icon(Icons.download_rounded),
          label: Text(
            state.isDownloading
                ? 'Downloading Gemma 4 E2B IT...'
                : 'Download On-Device Model (2.58 GB)',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('retry_wifi_check_button'),
                onPressed: state.isDownloading
                    ? null
                    : () => viewModel.checkReadiness(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Re-check Wi-Fi & Disk'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('switch_engine_mode_button'),
                onPressed: state.isDownloading
                    ? null
                    : () => _openEngineModeSheet(viewModel),
                icon: const Icon(Icons.router_outlined, size: 18),
                label: const Text('Switch Engine / LAN'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
