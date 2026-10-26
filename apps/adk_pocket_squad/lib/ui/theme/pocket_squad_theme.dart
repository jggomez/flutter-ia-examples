import 'package:flutter/material.dart';

import '../widgets/flutter_adk_widgets.dart';

/// Editorial Luxury Travel & Budget Concierge design system
/// ("Horizon Obsidian & Sunset Amber/Teal").
abstract final class PocketSquadTheme {
  // Core surfaces (Obsidian Night Sky)
  static const Color obsidianDeep = Color(0xFF0B101E);
  static const Color obsidianSurface = Color(0xFF131B2E);
  static const Color obsidianElevated = Color(0xFF1C2640);
  static const Color obsidianBorder = Color(0xFF283556);

  // Brand accents
  static const Color sunsetAmber = Color(0xFFF59E0B);
  static const Color sunsetAmberSoft = Color(0xFFFBBF24);
  static const Color tropicalTeal = Color(0xFF14B8A6);
  static const Color compassCyan = Color(0xFF06B6D4);
  static const Color emeraldAudit = Color(0xFF10B981);
  static const Color roseOverBudget = Color(0xFFF43F5E);
  static const Color auroraViolet = Color(0xFF8B5CF6);
  static const Color coordinatorViolet = Color(0xFF8B5CF6);

  // Semantic agent colors
  static const Color coordinatorAgentColor = coordinatorViolet;
  static const Color scoutAgentColor = compassCyan;
  static const Color budgetAuditorAgentColor = emeraldAudit;
  static const Color conciergeAgentColor = sunsetAmber;

  // Light mode surfaces
  static const Color ivoryBackground = Color(0xFFF8FAFC);
  static const Color ivorySurface = Color(0xFFFFFFFF);
  static const Color ivoryContainer = Color(0xFFF1F5F9);

  /// Resolves the semantic accent color for an ADK agent or author identifier.
  static Color agentColor(String? author) {
    final normalized = (author ?? '').trim().toLowerCase();
    if (normalized.contains('coordinator') ||
        normalized.contains('transfer_to_agent')) {
      return coordinatorViolet;
    }
    if (normalized.contains('scout')) {
      return scoutAgentColor;
    }
    if (normalized.contains('budget') || normalized.contains('audit')) {
      return budgetAuditorAgentColor;
    }
    if (normalized.contains('concierge')) {
      return conciergeAgentColor;
    }
    if (normalized.contains('tool')) {
      return tropicalTeal;
    }
    return sunsetAmber;
  }

  /// Resolves a concise human-readable role badge label for an ADK agent.
  static String agentBadgeLabel(String? author) {
    final normalized = (author ?? '').trim().toLowerCase();
    if (normalized.contains('coordinator')) {
      return 'Coordinator • Intake';
    }
    if (normalized.contains('scout')) {
      return '1 · Scout Agent · World Knowledge';
    }
    if (normalized.contains('budget') || normalized.contains('audit')) {
      return '2 · Budget Auditor · Deterministic Math';
    }
    if (normalized.contains('concierge')) {
      return '3 · Executive Concierge · Trip Vault';
    }
    if (normalized.contains('tool')) {
      return 'ADK FunctionTool';
    }
    if (normalized.isEmpty) {
      return 'Pocket Squad Agent';
    }
    return author!;
  }

  /// Resolves a human-readable editorial role badge title for an ADK agent.
  static String agentBadgeTitle(String? author) => agentBadgeLabel(author);

  /// Resolves the leading icon for an ADK agent role.
  static IconData agentIcon(String? author) {
    final normalized = (author ?? '').trim().toLowerCase();
    if (normalized.contains('coordinator')) {
      return Icons.support_agent_outlined;
    }
    if (normalized.contains('scout')) {
      return Icons.explore_outlined;
    }
    if (normalized.contains('budget') || normalized.contains('audit')) {
      return Icons.calculate_outlined;
    }
    if (normalized.contains('concierge')) {
      return Icons.luggage_outlined;
    }
    if (normalized.contains('tool')) {
      return Icons.build_circle_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  /// Default Dark Mode `ThemeData` ("Horizon Obsidian & Sunset Amber/Teal").
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: sunsetAmber,
      onPrimary: Color(0xFF140D00),
      primaryContainer: Color(0xFF3B2704),
      onPrimaryContainer: Color(0xFFFDE68A),
      secondary: tropicalTeal,
      onSecondary: Color(0xFF022C22),
      secondaryContainer: Color(0xFF113E3B),
      onSecondaryContainer: Color(0xFF99F6E4),
      tertiary: compassCyan,
      onTertiary: Color(0xFF022831),
      tertiaryContainer: Color(0xFF0E3A4A),
      onTertiaryContainer: Color(0xFFA5F3FC),
      error: roseOverBudget,
      onError: Colors.white,
      surface: obsidianDeep,
      onSurface: Color(0xFFF1F5F9),
      onSurfaceVariant: Color(0xFF94A3B8),
      surfaceContainerLowest: Color(0xFF070B14),
      surfaceContainerLow: obsidianSurface,
      surfaceContainer: Color(0xFF162038),
      surfaceContainerHigh: obsidianElevated,
      surfaceContainerHighest: Color(0xFF233050),
      outline: Color(0xFF475569),
      outlineVariant: obsidianBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: obsidianDeep,
      appBarTheme: const AppBarTheme(
        backgroundColor: obsidianDeep,
        foregroundColor: Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: obsidianSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: obsidianBorder, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: obsidianSurface,
        indicatorColor: sunsetAmber.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? sunsetAmber : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? sunsetAmber : const Color(0xFF94A3B8),
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: obsidianElevated,
        selectedColor: sunsetAmber.withValues(alpha: 0.2),
        side: const BorderSide(color: obsidianBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: obsidianElevated,
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: obsidianBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: obsidianBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: sunsetAmber, width: 1.5),
        ),
      ),
      dividerTheme: const DividerThemeData(color: obsidianBorder, thickness: 1),
    );
  }

  /// Crisp Editorial Light Mode `ThemeData`.
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: Color(0xFFD97706),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFEF3C7),
      onPrimaryContainer: Color(0xFF78350F),
      secondary: Color(0xFF0D9488),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFCCFBF1),
      onSecondaryContainer: Color(0xFF134E4A),
      tertiary: Color(0xFF0891B2),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFCFFAFE),
      onTertiaryContainer: Color(0xFF164E63),
      error: Color(0xFFE11D48),
      onError: Colors.white,
      surface: ivoryBackground,
      onSurface: Color(0xFF0F172A),
      onSurfaceVariant: Color(0xFF475569),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: ivorySurface,
      surfaceContainer: ivoryContainer,
      surfaceContainerHigh: Color(0xFFE2E8F0),
      surfaceContainerHighest: Color(0xFFCBD5E1),
      outline: Color(0xFF94A3B8),
      outlineVariant: Color(0xFFCBD5E1),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ivoryBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: ivoryBackground,
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: ivorySurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  /// Builds an [AdkChatThemeData] matching the active Material 3 [theme].
  static AdkChatThemeData adkChatTheme(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return AdkChatThemeData(
      backgroundColor: isDark ? obsidianDeep : ivoryBackground,
      userBubbleColor: sunsetAmber,
      userTextStyle: const TextStyle(
        color: Color(0xFF140D00),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      modelBubbleColor: isDark ? obsidianSurface : ivorySurface,
      modelTextStyle: TextStyle(
        color: theme.colorScheme.onSurface,
        fontSize: 14,
        height: 1.45,
      ),
      inputBackgroundColor: isDark ? obsidianElevated : ivoryContainer,
      sendButtonColor: sunsetAmber,
      sendButtonIconColor: const Color(0xFF140D00),
      inputBorderRadius: BorderRadius.circular(22),
      showAvatars: true,
    );
  }
}
