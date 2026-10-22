import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../view_models/model_download_view_model.dart';

/// Shown by `ChatTabRoot` while the on-device model has not finished
/// downloading: hero onboarding card with privacy guarantees, model specs,
/// live Wi-Fi status, and download progress indicators.
class ModelSetupScreen extends ConsumerWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelDownloadViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Assistant Setup')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: state.when(
                data: (status) => _StatusView(status: status),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    key: ValueKey('modelSetupLoading'),
                  ),
                ),
                error: (error, stackTrace) => _ErrorView(message: '$error'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusView extends ConsumerWidget {
  const _StatusView({required this.status});

  final ModelDownloadStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (status.phase) {
      case ModelDownloadPhase.ready:
        return const SizedBox.shrink();

      case ModelDownloadPhase.notDownloaded:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _HeroOnboardingCard(),
            const SizedBox(height: 10),
            const _ModelSpecsCard(),
            const SizedBox(height: 14),
            _DownloadCta(
              label: 'Download model (~529 MB)',
              onPressed: () => _confirmAndStartDownload(context, ref),
            ),
          ],
        );

      case ModelDownloadPhase.downloading:
        return _DownloadingCard(status: status);

      case ModelDownloadPhase.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ErrorView(message: status.errorMessage ?? 'Download failed.'),
            const SizedBox(height: 16),
            _DownloadCta(
              label: 'Retry download',
              onPressed: () => _confirmAndStartDownload(context, ref),
            ),
          ],
        );
    }
  }

  Future<void> _confirmAndStartDownload(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifier = ref.read(modelDownloadViewModelProvider.notifier);
    final isWifi = await notifier.checkWifiConnected();
    if (!context.mounted) return;

    final confirmedToken = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _ConfirmModelDownloadDialog(isWifiConnected: isWifi),
    );
    if (confirmedToken == null || !context.mounted) return;

    await notifier.startDownload(
      authToken: confirmedToken.isEmpty ? null : confirmedToken,
    );
  }
}

class _HeroOnboardingCard extends StatelessWidget {
  const _HeroOnboardingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withAlpha(35),
                    colorScheme.secondary.withAlpha(35),
                  ],
                ),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.auto_awesome_motion_rounded,
                size: 28,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'On-Device AI Assistant',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              '100% Offline & Private',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Runs entirely on your phone silicon without cloud telemetry.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _PrivacyBadge(
                  icon: Icons.cloud_off_rounded,
                  label: 'Zero Cloud Telemetry',
                ),
                _PrivacyBadge(
                  icon: Icons.memory_rounded,
                  label: 'On-Device Silicon',
                ),
                _PrivacyBadge(
                  icon: Icons.lock_outline_rounded,
                  label: 'No Account Required',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSpecsCard extends ConsumerWidget {
  const _ModelSpecsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notifier = ref.read(modelDownloadViewModelProvider.notifier);

    return Card(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.layers_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Model Specs',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                FutureBuilder<bool>(
                  future: notifier.checkWifiConnected(),
                  builder: (context, snapshot) {
                    final isWifi = snapshot.data ?? true;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
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
                            size: 12,
                            color: isWifi
                                ? colorScheme.onSecondaryContainer
                                : colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isWifi ? 'Wi-Fi Connected' : 'No Wi-Fi',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
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
            const Divider(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 2,
              children: [
                Text(
                  'Model: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Gemma 3 1B-IT (int4)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 2,
              children: [
                Text(
                  'Storage: ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '~529 MB (LiteRT-LM)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _DownloadingCard extends StatelessWidget {
  const _DownloadingCard({required this.status});

  final ModelDownloadStatus status;

  String _formatMb(int bytes) {
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = status.progress;
    final percent = progress != null
        ? (progress * 100).toStringAsFixed(0)
        : '0';

    final downloadedMb = _formatMb(status.bytesDownloaded);
    final totalMb = status.totalBytes != null
        ? _formatMb(status.totalBytes!)
        : '529.0';

    return Card(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.downloading_rounded,
                size: 28,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Downloading On-Device Model',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Gemma 3 1B-IT is downloading over Wi-Fi…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 10),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$downloadedMb MB / ~$totalMb MB',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onPrimaryContainer,
                    ),
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

class _ConfirmModelDownloadDialog extends StatefulWidget {
  const _ConfirmModelDownloadDialog({required this.isWifiConnected});

  final bool isWifiConnected;

  @override
  State<_ConfirmModelDownloadDialog> createState() =>
      _ConfirmModelDownloadDialogState();
}

class _ConfirmModelDownloadDialogState
    extends State<_ConfirmModelDownloadDialog> {
  final TextEditingController _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isWifi = widget.isWifiConnected;

    return AlertDialog(
      key: const ValueKey('confirmModelDownloadDialog'),
      title: const Text('Download on-device AI model?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemma 3 1B-IT (~529 MB) will be downloaded directly onto this '
              'device for offline conference Q&A.',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isWifi
                    ? colorScheme.secondaryContainer.withAlpha(128)
                    : colorScheme.errorContainer.withAlpha(128),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isWifi ? colorScheme.secondary : colorScheme.error,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isWifi ? Icons.wifi : Icons.wifi_off,
                    color: isWifi ? colorScheme.primary : colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWifi
                          ? 'Wi-Fi connected — ready to download'
                          : 'Wi-Fi not connected — please connect to Wi-Fi '
                                'before downloading',
                      style: TextStyle(
                        color: isWifi ? colorScheme.primary : colorScheme.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('hfTokenTextField'),
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'HuggingFace Token (optional if set via build)',
                hintText: 'hf_...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancelDownloadDialogButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirmDownloadDialogButton'),
          onPressed: isWifi
              ? () => Navigator.of(context).pop(_tokenController.text.trim())
              : null,
          child: const Text('Download on Wi-Fi'),
        ),
      ],
    );
  }
}

class _DownloadCta extends StatelessWidget {
  const _DownloadCta({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: const ValueKey('startDownloadButton'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.download_rounded, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withAlpha(128),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error),
      ),
      child: Text(
        key: const ValueKey('modelSetupError'),
        'Error: $message',
        style: TextStyle(
          color: colorScheme.onErrorContainer,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
