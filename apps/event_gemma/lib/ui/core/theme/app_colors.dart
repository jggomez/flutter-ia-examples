import 'package:flutter/material.dart';

/// Centralized color palette and visual tokens for the Event Gemma app.
abstract final class AppColors {
  // Brand Primaries & Secondaries
  static const primaryIndigo = Color(0xFF4F46E5);
  static const darkPrimaryViolet = Color(0xFF6366F1);
  static const secondaryCyan = Color(0xFF06B6D4);
  static const darkSecondaryTeal = Color(0xFF14B8A6);

  // Light Palette Surfaces
  static const lightSurface = Color(0xFFFAFBFD);
  static const lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const lightSurfaceContainerLow = Color(0xFFF3F4F9);
  static const lightSurfaceContainer = Color(0xFFECEFF6);
  static const lightSurfaceContainerHigh = Color(0xFFE5E8F1);
  static const lightSurfaceContainerHighest = Color(0xFFDEE2EC);
  static const lightOutline = Color(0xFFC7CCD9);
  static const lightOutlineVariant = Color(0xFFE2E5EE);
  static const lightPrimaryContainer = Color(0xFFEEF2FF);
  static const lightOnPrimaryContainer = Color(0xFF312E81);

  // Dark Palette Surfaces
  static const darkSurface = Color(0xFF0F172A);
  static const darkSurfaceContainerLowest = Color(0xFF090D16);
  static const darkSurfaceContainerLow = Color(0xFF141C31);
  static const darkSurfaceContainer = Color(0xFF1B253D);
  static const darkSurfaceContainerHigh = Color(0xFF23304E);
  static const darkSurfaceContainerHighest = Color(0xFF2D3C61);
  static const darkOutline = Color(0xFF475569);
  static const darkOutlineVariant = Color(0xFF2A364F);
  static const darkPrimaryContainer = Color(0xFF312E81);
  static const darkOnPrimaryContainer = Color(0xFFE0E7FF);

  // Track Badge Colors - Engineering (Violet / Indigo)
  static const trackEngineeringBgLight = Color(0xFFEEF2FF);
  static const trackEngineeringFgLight = Color(0xFF4338CA);
  static const trackEngineeringBorderLight = Color(0xFFC7D2FE);
  static const trackEngineeringBgDark = Color(0xFF1E1B4B);
  static const trackEngineeringFgDark = Color(0xFFA5B4FC);
  static const trackEngineeringBorderDark = Color(0xFF3730A3);

  // Track Badge Colors - Product & Design (Cyan / Teal)
  static const trackProductBgLight = Color(0xFFECFEFF);
  static const trackProductFgLight = Color(0xFF0E7490);
  static const trackProductBorderLight = Color(0xFFA5F3FC);
  static const trackProductBgDark = Color(0xFF083344);
  static const trackProductFgDark = Color(0xFF67E8F9);
  static const trackProductBorderDark = Color(0xFF155E75);

  // Accents & Status
  static const successGreen = Color(0xFF10B981);
  static const warningAmber = Color(0xFFF59E0B);
  static const errorRed = Color(0xFFEF4444);
}
