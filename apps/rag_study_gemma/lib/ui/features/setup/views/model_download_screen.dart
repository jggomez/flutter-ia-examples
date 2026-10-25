import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../view_models/model_download_view_model.dart';

/// Onboarding and download screen for StudyGemma's dual on-device AI stack:
/// - Stage 1: EmbeddingGemma 2 (270M) — 157 MB, 768-dim vectors, SQLite vec0
/// - Stage 2: Gemma 4 E2B IT — 2.58 GB, Mixed 2/4/8-bit, 4096-token context
class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  final TextEditingController _hfTokenController = TextEditingController();

  @override
  void dispose() {
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndStartDownload() async {
    final notifier = ref.read(modelDownloadViewModelProvider.notifier);
    final isWifi = await notifier.checkWifi();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          _ConfirmDualModelDownloadDialog(isWifiConnected: isWifi),
    );
    if (confirmed != true || !mounted) return;

    await notifier.startDownload(hfToken: _hfTokenController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(modelDownloadViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories_rounded, size: 22),
            SizedBox(width: 10),
            Text('StudyGemma Setup'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: state.when(
                data: (status) => _buildBodyForStatus(context, status),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    key: ValueKey('modelDownloadLoading'),
                  ),
                ),
                error: (error, _) => _ErrorBanner(
                  message: '$error',
                  onRetry: _confirmAndStartDownload,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBodyForStatus(BuildContext context, ModelDownloadStatus status) {
    switch (status.phase) {
      case ModelDownloadPhase.checking:
        return const Center(child: CircularProgressIndicator());

      case ModelDownloadPhase.ready:
        return const SizedBox.shrink();

      case ModelDownloadPhase.downloadingEmbedding:
      case ModelDownloadPhase.downloadingLlm:
        return _LiveDownloadProgressCard(status: status);

      case ModelDownloadPhase.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeroDualModelCard(),
            const SizedBox(height: 12),
            _ErrorBanner(
              message:
                  status.errorMessage ??
                  'Failed to download on-device AI models.',
              onRetry: _confirmAndStartDownload,
            ),
          ],
        );

      case ModelDownloadPhase.notDownloaded:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeroDualModelCard(),
            const SizedBox(height: 12),
            const _DualModelArchitectureCard(),
            const SizedBox(height: 12),
            _TokenAndWifiCard(tokenController: _hfTokenController),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('startDownloadButton'),
              onPressed: _confirmAndStartDownload,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: const Text('Download Study AI Models (~2.74 GB)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _HeroDualModelCard extends StatelessWidget {
  const _HeroDualModelCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.school_rounded,
                size: 30,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'On-Device PDF Vector RAG Companion',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '100% Offline · Embeddings 2.0 + SQLite vec0 + Gemma 4',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Index your textbooks, lecture notes, and research PDFs locally '
              'and ask grounded questions with exact page citations.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DualModelArchitectureCard extends StatelessWidget {
  const _DualModelArchitectureCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Dual On-Device AI Stack',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            const _ModelSpecRow(
              badge: 'Stage 1',
              title: 'EmbeddingGemma 2 (270M)',
              subtitle: '157 MB · 768-dim vectors · SQLite vec0',
              icon: Icons.scatter_plot_rounded,
            ),
            const SizedBox(height: 10),
            const _ModelSpecRow(
              badge: 'Stage 2',
              title: 'Gemma 4 E2B IT',
              subtitle: '2.58 GB · Mixed 2/4/8-bit · 4096-token context',
              icon: Icons.psychology_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelSpecRow extends StatelessWidget {
  const _ModelSpecRow({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String badge;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: colorScheme.onSecondaryContainer),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TokenAndWifiCard extends ConsumerStatefulWidget {
  const _TokenAndWifiCard({required this.tokenController});

  final TextEditingController tokenController;

  @override
  ConsumerState<_TokenAndWifiCard> createState() => _TokenAndWifiCardState();
}

class _TokenAndWifiCardState extends ConsumerState<_TokenAndWifiCard> {
  late Future<bool> _wifiFuture;

  @override
  void initState() {
    super.initState();
    _wifiFuture = ref.read(modelDownloadViewModelProvider.notifier).checkWifi();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'Network & HuggingFace Access',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FutureBuilder<bool>(
                  future: _wifiFuture,
                  builder: (context, snapshot) {
                    final isWifi = snapshot.data ?? true;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isWifi
                            ? colorScheme.secondaryContainer
                            : colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isWifi
                                ? Icons.wifi_rounded
                                : Icons.wifi_off_rounded,
                            size: 13,
                            color: isWifi
                                ? colorScheme.onSecondaryContainer
                                : colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isWifi ? 'Wi-Fi Ready' : 'Wi-Fi Required',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isWifi
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('hfTokenTextField'),
              controller: widget.tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'HuggingFace Access Token (optional)',
                hintText: 'hf_...',
                prefixIcon: Icon(Icons.key_rounded, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Note: An ungated public mirror fallback is used automatically if no token is provided.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDownloadProgressCard extends StatelessWidget {
  const _LiveDownloadProgressCard({required this.status});

  final ModelDownloadStatus status;

  String _formatMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progressValue = status.progress;
    final percent = (progressValue * 100).round();
    final isEmbeddingStage =
        status.phase == ModelDownloadPhase.downloadingEmbedding;
    final modelName = status.currentModelName.isNotEmpty
        ? status.currentModelName
        : (isEmbeddingStage ? 'EmbeddingGemma 2 (270M)' : 'Gemma 4 E2B IT');
    final stageBadge = isEmbeddingStage ? 'Stage 1 of 2' : 'Stage 2 of 2';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  stageBadge,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Downloading $modelName',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: status.totalBytes > 0 ? progressValue : null,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '${_formatMb(status.bytesReceived)} MB / ${_formatMb(status.totalBytes)} MB',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$percent%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDualModelDownloadDialog extends StatelessWidget {
  const _ConfirmDualModelDownloadDialog({required this.isWifiConnected});

  final bool isWifiConnected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      key: const ValueKey('confirmModelDownloadDialog'),
      title: const Text('Download StudyGemma AI Models?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'StudyGemma will download EmbeddingGemma 2 (157 MB) and '
            'Gemma 4 E2B IT (2.58 GB) — ~2.74 GB total — for 100% offline PDF RAG.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isWifiConnected
                  ? colorScheme.secondaryContainer
                  : colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  isWifiConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  size: 18,
                  color: isWifiConnected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isWifiConnected
                        ? 'Unmetered Wi-Fi detected — ready to download.'
                        : 'Wi-Fi not detected — Wi-Fi is required to complete the download.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isWifiConnected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancelDownloadDialogButton'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirmDownloadDialogButton'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Start Download'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    key: const ValueKey('modelDownloadErrorText'),
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('startDownloadButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry Download'),
            ),
          ],
        ),
      ),
    );
  }
}
