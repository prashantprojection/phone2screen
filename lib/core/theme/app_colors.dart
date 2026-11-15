import 'package:material_ui/material_ui.dart';

/// Neutral Obsidian dark and Google Material 3 light color palette for Phone2Screen.
abstract final class AppColors {
  // Brand & status accents
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color cyanAccent = Color(0xFF06B6D4);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFF43F5E);

  // Neutral Obsidian dark surfaces
  static const Color backgroundDark = Color(0xFF0F0F11);
  static const Color surfaceDark = Color(0xFF18191C);
  static const Color surfaceElevatedDark = Color(0xFF23252A);
  static const Color borderDark = Color(0xFF2D3037);

  // Google Material 3 neutral light surfaces
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF1F3F4);
  static const Color borderLight = Color(0xFFE2E5E9);

  // Typography colors
  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textSecondaryLight = Color(0xFF5F6368);
  static const Color textPrimaryDark = Color(0xFFF3F4F6);
  static const Color textSecondaryDark = Color(0xFF9AA0A6);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, cyanAccent],
    begin: .topLeft,
    end: .bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [accentGreen, Color(0xFF34D399)],
    begin: .topLeft,
    end: .bottomRight,
  );
}
