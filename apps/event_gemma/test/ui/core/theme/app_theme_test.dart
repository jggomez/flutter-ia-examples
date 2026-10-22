import 'package:event_gemma/ui/core/theme/app_colors.dart';
import 'package:event_gemma/ui/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors', () {
    test('defines primary deep indigo and secondary luminous cyan', () {
      expect(AppColors.primaryIndigo, const Color(0xFF4F46E5));
      expect(AppColors.secondaryCyan, const Color(0xFF06B6D4));
      expect(AppColors.darkPrimaryViolet, const Color(0xFF6366F1));
      expect(AppColors.darkSecondaryTeal, const Color(0xFF14B8A6));
    });

    test('provides distinct colors for engineering and product tracks', () {
      expect(AppColors.trackEngineeringBgLight, isNotNull);
      expect(AppColors.trackEngineeringFgLight, isNotNull);
      expect(AppColors.trackProductBgLight, isNotNull);
      expect(AppColors.trackProductFgLight, isNotNull);
    });
  });

  group('AppTheme', () {
    test('light theme conforms to Material 3 and custom tokens', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AppColors.primaryIndigo);
      expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      final border = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(border.borderRadius, BorderRadius.circular(16));
    });

    test('dark theme conforms to Material 3 and dark tokens', () {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.darkPrimaryViolet);
      expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      final border = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(border.borderRadius, BorderRadius.circular(16));
    });
  });
}
