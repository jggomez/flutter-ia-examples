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
        return _DownloadCta(
          label: 'Download model (~529 MB)',
          onPressed: () =>
              ref.read(modelDownloadViewModelProvider.notifier).startDownload(),
        );
      case ModelDownloadPhase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Downloading model…'),
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
              onPressed: () => ref
                  .read(modelDownloadViewModelProvider.notifier)
                  .startDownload(),
            ),
          ],
        );
    }
  }

  String _progressLabel(ModelDownloadStatus status) {
    final progress = status.progress;
    if (progress == null) return '${status.bytesDownloaded} bytes';
    return '${(progress * 100).toStringAsFixed(0)}%';
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
