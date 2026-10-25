import 'package:flutter/material.dart';

import '../../../domain/models/ingestion_progress.dart';

/// Renders the 4-stage on-device PDF RAG ingestion pipeline:
/// `1. Validate PDF` → `2. Extract Pages` → `3. Sliding-Window Chunks`
/// → `4. EmbeddingGemma 2 + SQLite vec0` with live step indicators,
/// progress bar, and chunk/page counter.
class IngestionProgressCard extends StatelessWidget {
  const IngestionProgressCard({super.key, required this.progress});

  final IngestionProgress progress;

  static const List<({IngestionStage stage, String label})> _pipelineSteps = [
    (stage: IngestionStage.validating, label: '1. Validate PDF'),
    (stage: IngestionStage.extracting, label: '2. Extract Pages'),
    (stage: IngestionStage.chunking, label: '3. Sliding-Window Chunks'),
    (
      stage: IngestionStage.embedding,
      label: '4. EmbeddingGemma 2 + SQLite vec0',
    ),
  ];

  int _stageRank(IngestionStage stage) {
    switch (stage) {
      case IngestionStage.idle:
        return 0;
      case IngestionStage.validating:
        return 1;
      case IngestionStage.extracting:
        return 2;
      case IngestionStage.chunking:
        return 3;
      case IngestionStage.embedding:
        return 4;
      case IngestionStage.completed:
        return 5;
      case IngestionStage.failed:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentRank = _stageRank(progress.stage);
    final hasCounter = progress.total > 0;

    return Card(
      key: const ValueKey('ingestionProgressCard'),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.primary.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Indexing Study PDF On-Device',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (hasCounter)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${progress.current} / ${progress.total}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            if (progress.message.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                progress.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: hasCounter ? progress.progress : null,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final step in _pipelineSteps)
                  _StepChip(
                    label: step.label,
                    isCompleted: currentRank > _stageRank(step.stage),
                    isActive: currentRank == _stageRank(step.stage),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.isCompleted,
    required this.isActive,
  });

  final String label;
  final bool isCompleted;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;

    if (isCompleted) {
      bgColor = colorScheme.secondaryContainer;
      fgColor = colorScheme.onSecondaryContainer;
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      bgColor = colorScheme.primaryContainer;
      fgColor = colorScheme.onPrimaryContainer;
      icon = Icons.sync_rounded;
    } else {
      bgColor = colorScheme.surfaceContainerHighest.withAlpha(110);
      fgColor = colorScheme.onSurfaceVariant;
      icon = Icons.radio_button_unchecked_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive || isCompleted
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }
}
