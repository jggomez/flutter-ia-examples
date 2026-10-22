import 'package:flutter/material.dart';

import '../../../domain/models/conference_track.dart';
import '../theme/app_colors.dart';

/// Reusable categorical track badge with distinct color schemes per track.
class TrackBadge extends StatelessWidget {
  const TrackBadge({
    super.key,
    required this.track,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  final ConferenceTrack track;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (bg, fg, border) = switch (track) {
      ConferenceTrack.engineering =>
        isDark
            ? (
                AppColors.trackEngineeringBgDark,
                AppColors.trackEngineeringFgDark,
                AppColors.trackEngineeringBorderDark,
              )
            : (
                AppColors.trackEngineeringBgLight,
                AppColors.trackEngineeringFgLight,
                AppColors.trackEngineeringBorderLight,
              ),
      ConferenceTrack.productAndDesign =>
        isDark
            ? (
                AppColors.trackProductBgDark,
                AppColors.trackProductFgDark,
                AppColors.trackProductBorderDark,
              )
            : (
                AppColors.trackProductBgLight,
                AppColors.trackProductFgLight,
                AppColors.trackProductBorderLight,
              ),
    };

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Text(
        track.label,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
