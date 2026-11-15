import 'package:material_ui/material_ui.dart';

/// Studio Dark Slate and crisp Light color palette for Phone2Screen.
abstract final class AppColors {
  // Brand & status accents
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color cyanAccent = Color(0xFF06B6D4);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFF43F5E);

  // Studio dark surfaces
  static const Color backgroundDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF131B2E);
  static const Color surfaceElevatedDark = Color(0xFF1E293B);
  static const Color borderDark = Color(0xFF334155);

  // Crisp light surfaces
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Typography colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

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
