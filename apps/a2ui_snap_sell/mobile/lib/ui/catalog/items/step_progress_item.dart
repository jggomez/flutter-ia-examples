import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'data_context_binding_ext.dart';

final Schema _schema = S.object(
  description: 'Multi-step wizard header displaying selling flow progress.',
  properties: <String, Schema>{
    'currentStep': S.integer(minimum: 1),
    'totalSteps': S.integer(minimum: 1),
    'stepLabels': S.list(items: S.string(), minItems: 1),
    'subtitle': A2uiSchemas.stringReference(
      description: 'Optional status subtitle for the active step.',
    ),
    'stepTitle': A2uiSchemas.stringReference(
      description: 'Optional title for the active step.',
    ),
  },
  required: <String>['currentStep', 'totalSteps', 'stepLabels'],
);

/// The `StepProgress` custom A2UI catalog item.
final CatalogItem stepProgressItem = CatalogItem(
  name: 'StepProgress',
  dataSchema: _schema,
  widgetBuilder: (CatalogItemContext itemContext) {
    final JsonMap json = itemContext.data as JsonMap;
    final int currentStep = (json['currentStep'] as num?)?.toInt() ?? 1;
    final int totalSteps = (json['totalSteps'] as num?)?.toInt() ?? 4;
    final List<String> stepLabels =
        (json['stepLabels'] as List<Object?>?)
            ?.map((Object? e) => e.toString())
            .toList(growable: false) ??
        const <String>[];

    final ValueListenable<String?> subtitleNotifier = itemContext.dataContext
        .subscribeToString(json['subtitle']);
    final ValueListenable<String?> stepTitleNotifier = itemContext.dataContext
        .subscribeToString(json['stepTitle']);

    return _StepProgressWidget(
      currentStep: currentStep,
      totalSteps: totalSteps,
      stepLabels: stepLabels,
      subtitleNotifier: subtitleNotifier,
      stepTitleNotifier: stepTitleNotifier,
    );
  },
);

class _StepProgressWidget extends StatelessWidget {
  const _StepProgressWidget({
    required this.currentStep,
    required this.totalSteps,
    required this.stepLabels,
    required this.subtitleNotifier,
    required this.stepTitleNotifier,
  });

  final int currentStep;
  final int totalSteps;
  final List<String> stepLabels;
  final ValueListenable<String?> subtitleNotifier;
  final ValueListenable<String?> stepTitleNotifier;

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
                  ValueListenableBuilder<String?>(
                    valueListenable: stepTitleNotifier,
                    builder:
                        (BuildContext context, String? stepTitle, Widget? _) {
                          final String displayTitle =
                              (stepTitle != null && stepTitle.isNotEmpty)
                              ? stepTitle
                              : activeStepLabel;
                          if (displayTitle.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            displayTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
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
                  children: List<Widget>.generate(stepLabels.length, (int i) {
                    final int stepNumber = i + 1;
                    final bool isCompleted = stepNumber < currentStep;
                    final bool isCurrent = stepNumber == currentStep;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
                            stepLabels[i],
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
              ValueListenableBuilder<String?>(
                valueListenable: subtitleNotifier,
                builder: (BuildContext context, String? subtitle, Widget? _) {
                  if (subtitle == null || subtitle.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
