import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../snap_sell_catalog.dart';

/// `StepProgress`: multi-step wizard header of every selling surface.
final ComponentImplementation stepProgressComponent =
    implementContractComponent('StepProgress', _build);

Widget _build(
  BuildContext context,
  ComponentNode<ComponentImplementation> node,
  ComponentProps props,
  ChildWidgetBuilder buildChild,
) {
  return StepProgressView(
    currentStep: props.number('currentStep')?.toInt() ?? 1,
    totalSteps: props.number('totalSteps')?.toInt() ?? 4,
    stepLabels: props
        .list('stepLabels')
        .map((Object? e) => ComponentProps.asString(e) ?? '')
        .toList(growable: false),
    subtitle: props.string('subtitle'),
  );
}

class StepProgressView extends StatelessWidget {
  const StepProgressView({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabels,
    this.subtitle,
  });

  final int currentStep;
  final int totalSteps;
  final List<String> stepLabels;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final double progress = totalSteps > 0
        ? (currentStep.clamp(0, totalSteps) / totalSteps)
        : 0.0;
    final String activeStepLabel =
        (currentStep >= 1 && currentStep <= stepLabels.length)
        ? stepLabels[currentStep - 1]
        : '';

    return Semantics(
      container: true,
      label: 'Step $currentStep of $totalSteps',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Step $currentStep of $totalSteps',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (activeStepLabel.isNotEmpty)
                    Text(
                      activeStepLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              if (stepLabels.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    for (int i = 0; i < stepLabels.length; i++)
                      _StepChip(
                        label: stepLabels[i],
                        isCompleted: i + 1 < currentStep,
                        isCurrent: i + 1 == currentStep,
                      ),
                  ],
                ),
              ],
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
  });

  final String label;
  final bool isCompleted;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent
            ? colorScheme.primaryContainer
            : isCompleted
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isCompleted
                ? Icons.check_circle
                : isCurrent
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 14,
            color: isCurrent
                ? colorScheme.primary
                : isCompleted
                ? colorScheme.secondary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
