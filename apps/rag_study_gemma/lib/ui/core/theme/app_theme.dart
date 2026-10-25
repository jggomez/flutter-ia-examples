import 'package:flutter/material.dart';

/// Material 3 AI Study Companion theme for StudyGemma.
///
/// Combines Deep Academic Indigo/Sapphire primaries with Emerald/Teal
/// AI accents, high-contrast surface containers, and 16-20px rounded geometry.
abstract final class AppTheme {
  // Light palette
  static const Color primaryIndigo = Color(0xFF1E40AF);
  static const Color lightPrimaryContainer = Color(0xFFDBEAFE);
  static const Color lightOnPrimaryContainer = Color(0xFF1E3A8A);
  static const Color accentEmerald = Color(0xFF059669);
  static const Color lightSecondaryContainer = Color(0xFFD1FAE5);
  static const Color lightOnSecondaryContainer = Color(0xFF065F46);
  static const Color accentTeal = Color(0xFF0D9488);
  static const Color lightTertiaryContainer = Color(0xFFCCFBF1);
  static const Color lightOnTertiaryContainer = Color(0xFF115E59);

  // Dark palette
  static const Color darkPrimarySapphire = Color(0xFF60A5FA);
  static const Color darkPrimaryContainer = Color(0xFF1E3A8A);
  static const Color darkOnPrimaryContainer = Color(0xFFDBEAFE);
  static const Color darkAccentEmerald = Color(0xFF34D399);
  static const Color darkSecondaryContainer = Color(0xFF064E3B);
  static const Color darkOnSecondaryContainer = Color(0xFFD1FAE5);
  static const Color darkAccentTeal = Color(0xFF2DD4BF);
  static const Color darkTertiaryContainer = Color(0xFF134E4A);
  static const Color darkOnTertiaryContainer = Color(0xFFCCFBF1);

  // Semantic status colors
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFDC2626);

  /// Light Material 3 theme.
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primaryIndigo,
      onPrimary: Colors.white,
      primaryContainer: lightPrimaryContainer,
      onPrimaryContainer: lightOnPrimaryContainer,
      secondary: accentEmerald,
      onSecondary: Colors.white,
      secondaryContainer: lightSecondaryContainer,
      onSecondaryContainer: lightOnSecondaryContainer,
      tertiary: accentTeal,
      onTertiary: Colors.white,
      tertiaryContainer: lightTertiaryContainer,
      onTertiaryContainer: lightOnTertiaryContainer,
      error: errorRed,
      onError: Colors.white,
      errorContainer: const Color(0xFFFEE2E2),
      onErrorContainer: const Color(0xFF991B1B),
      surface: const Color(0xFFF8FAFC),
      onSurface: const Color(0xFF0F172A),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF1F5F9),
      surfaceContainer: const Color(0xFFE2E8F0),
      surfaceContainerHigh: const Color(0xFFCBD5E1),
      surfaceContainerHighest: const Color(0xFFE2E8F0),
      onSurfaceVariant: const Color(0xFF475569),
      outline: const Color(0xFF94A3B8),
      outlineVariant: const Color(0xFFCBD5E1),
      shadow: Colors.black.withAlpha(18),
    );

    return _buildTheme(colorScheme);
  }

  /// Dark Material 3 theme.
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: darkPrimarySapphire,
      onPrimary: const Color(0xFF0F172A),
      primaryContainer: darkPrimaryContainer,
      onPrimaryContainer: darkOnPrimaryContainer,
      secondary: darkAccentEmerald,
      onSecondary: const Color(0xFF022C22),
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: darkOnSecondaryContainer,
      tertiary: darkAccentTeal,
      onTertiary: const Color(0xFF042F2E),
      tertiaryContainer: darkTertiaryContainer,
      onTertiaryContainer: darkOnTertiaryContainer,
      error: const Color(0xFFF87171),
      onError: const Color(0xFF450A0A),
      errorContainer: const Color(0xFF7F1D1D),
      onErrorContainer: const Color(0xFFFECACA),
      surface: const Color(0xFF0B1120),
      onSurface: const Color(0xFFF1F5F9),
      surfaceContainerLowest: const Color(0xFF070B14),
      surfaceContainerLow: const Color(0xFF111827),
      surfaceContainer: const Color(0xFF1E293B),
      surfaceContainerHigh: const Color(0xFF334155),
      surfaceContainerHighest: const Color(0xFF1E293B),
      onSurfaceVariant: const Color(0xFF94A3B8),
      outline: const Color(0xFF64748B),
      outlineVariant: const Color(0xFF334155),
      shadow: Colors.black.withAlpha(90),
    );

    return _buildTheme(colorScheme);
  }

  /// Alias for [lightTheme].
  static ThemeData get light => lightTheme;

  /// Alias for [darkTheme].
  static ThemeData get dark => darkTheme;

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 2,
        backgroundColor: colorScheme.surfaceContainerLowest,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.onPrimaryContainer);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.onPrimaryContainer,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withAlpha(140),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
