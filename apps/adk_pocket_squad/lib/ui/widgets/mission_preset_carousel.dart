import 'package:flutter/material.dart';

import '../../domain/models/squad_mission_preset.dart';
import '../theme/pocket_squad_theme.dart';

/// Horizontal carousel of curated luxury destination presets that launch
/// the 3-agent `SequentialAgent` mission with one tap.
class MissionPresetCarousel extends StatelessWidget {
  const MissionPresetCarousel({
    super.key,
    required this.presets,
    required this.onSelectPreset,
    this.enabled = true,
  });

  final List<SquadMissionPreset> presets;
  final ValueChanged<SquadMissionPreset> onSelectPreset;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 102,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: presets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = presets[index];
          final accent = Color(preset.accentHex);

          return InkWell(
            key: Key('preset_card_${preset.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? () => onSelectPreset(preset) : null,
            child: Container(
              width: 224,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PocketSquadTheme.obsidianSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.flight_takeoff, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          preset.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    preset.vibeTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${preset.days} Days · \$${preset.budgetUsd.toStringAsFixed(0)} USD',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        preset.currency,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
