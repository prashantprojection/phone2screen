import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Material 3 studio dark and light themes for Phone2Screen.
abstract final class AppTheme {
  static final ThemeData lightTheme = _buildTheme(brightness: .light);
  static final ThemeData darkTheme = _buildTheme(brightness: .dark);

  static ThemeData _buildTheme({required Brightness brightness}) {
    final isDark = brightness == .dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceHigh = isDark
        ? AppColors.surfaceElevatedDark
        : AppColors.surfaceElevatedLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final onSurface = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final onSurfaceMuted = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primaryBlue,
      secondary: AppColors.cyanAccent,
      surface: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceHigh,
      surfaceContainerHigh: surfaceHigh,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceMuted,
      outline: border,
      outlineVariant: border,
      error: AppColors.accentRed,
    );

    final cardShape = RoundedRectangleBorder(
      borderRadius: .circular(16),
      side: BorderSide(color: border),
    );
    final controlShape = RoundedRectangleBorder(borderRadius: .circular(12));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarThemeData(
        backgroundColor: bg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: cardShape,
        margin: .zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: controlShape,
          padding: const .symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: controlShape,
          padding: const .symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          side: BorderSide(color: border),
          padding: const .symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: .circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: .circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: .circular(12),
          borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: cardShape),
      snackBarTheme: SnackBarThemeData(
        behavior: .floating,
        shape: controlShape,
      ),
    );
  }
}
