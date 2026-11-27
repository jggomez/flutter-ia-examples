import 'package:flutter/material.dart';

import '../../../../../domain/models/jev_decision.dart';

const Map<String, String> _stageTitles = <String, String>{
  'photo': 'Photo',
  'form': 'Which questions to ask',
  'details': 'Your details',
  'damage_photo': 'Damage photo',
};

/// App bar button that opens [JevDecisionsSheet] for the last turn.
class JevDecisionsButton extends StatelessWidget {
  const JevDecisionsButton({required this.decisions, super.key});

  final List<JevDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final int changed = decisions.where((JevDecision d) => d.changedUi).length;
    return IconButton(
      key: const Key('jev_decisions_button'),
      tooltip: 'Jev decisions',
      onPressed: decisions.isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => JevDecisionsSheet(decisions: decisions),
            ),
      icon: Badge.count(
        count: changed,
        isLabelVisible: changed > 0,
        child: const Icon(Icons.psychology_alt_outlined),
      ),
    );
  }
}

/// Lists what Jev decided in the last turn, grouped by stage, with the
/// probability behind each answer and what the code did with it.
class JevDecisionsSheet extends StatelessWidget {
  const JevDecisionsSheet({required this.decisions, super.key});

  final List<JevDecision> decisions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, List<JevDecision>> byStage =
        <String, List<JevDecision>>{};
    for (final JevDecision d in decisions) {
      (byStage[d.stage] ??= <JevDecision>[]).add(d);
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('Jev decisions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Jev answers each question with a probability. The code turns the '
            'answers into this screen.',
            style: theme.textTheme.bodySmall,
          ),
          for (final MapEntry<String, List<JevDecision>> group
              in byStage.entries) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              _stageTitles[group.key] ?? group.key,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final JevDecision d in group.value) _DecisionTile(decision: d),
          ],
        ],
      ),
    );
  }
}

class _DecisionTile extends StatelessWidget {
  const _DecisionTile({required this.decision});

  final JevDecision decision;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool changed = decision.changedUi;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  decision.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: changed ? FontWeight.w600 : null,
                  ),
                ),
              ),
              Text(
                '${decision.answer} · ${(decision.probability * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: decision.probability.clamp(0, 1),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            color: changed ? colors.primary : colors.outline,
            backgroundColor: colors.surfaceContainerHighest,
          ),
          const SizedBox(height: 2),
          Text(
            decision.outcome,
            style: theme.textTheme.labelSmall?.copyWith(
              color: changed ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
