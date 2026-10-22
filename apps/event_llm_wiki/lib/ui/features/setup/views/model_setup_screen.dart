import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/model_download_status.dart';
import '../view_models/model_download_view_model.dart';

/// Shown by `ChatTabRoot` while the on-device model has not finished
/// downloading: a "Download model (~529 MB)" call to action, then a
/// progress indicator once `ModelDownloadViewModel.startDownload()` is
/// running (see `doc/adr/0005-model-download-flow.md`).
class ModelSetupScreen extends ConsumerWidget {
  const ModelSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelDownloadViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up the assistant')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: state.when(
              data: (status) => _StatusView(status: status),
              loading: () => const CircularProgressIndicator(
                key: ValueKey('modelSetupLoading'),
              ),
              error: (error, stackTrace) => _ErrorView(message: '$error'),
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
        // `ChatTabRoot` swaps this screen out once `ready`; render nothing
        // meaningful here in the brief instant before that happens.
        return const SizedBox.shrink();
      case ModelDownloadPhase.notDownloaded:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48),
            const SizedBox(height: 12),
            Text(
              'On-Device Conference Assistant',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Gemma 3 1B-IT (~529 MB) is downloaded once directly onto your '
              'mobile device over Wi-Fi for 100% offline agenda Q&A.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _DownloadCta(
              label: 'Download model (~529 MB)',
              onPressed: () => _confirmAndStartDownload(context, ref),
            ),
          ],
        );
      case ModelDownloadPhase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Downloading model on Wi-Fi…'),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: status.progress),
            const SizedBox(height: 8),
            Text(_progressLabel(status)),
          ],
        );
      case ModelDownloadPhase.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
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

  String _progressLabel(ModelDownloadStatus status) {
    final progress = status.progress;
    if (progress == null) return '${status.bytesDownloaded} bytes';
    return '${(progress * 100).toStringAsFixed(0)}%';
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
            const SizedBox(height: 12),
            Row(
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
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
      child: Text(label),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      key: const ValueKey('modelSetupError'),
      'Error: $message',
      textAlign: TextAlign.center,
    );
  }
}
