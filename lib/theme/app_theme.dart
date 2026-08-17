import 'package:flutter/material.dart';

/// JITSUGYO brand themed design for Shift Planner: pink/magenta + black,
/// matching the company logo colors.
class AppColors {
  static const Color primary = Color(0xFFEA5F98); // brand pink/magenta
  static const Color primaryDeep = Color(0xFFC4275F); // deep red-pink
  static const Color accentPink = Color(0xFFEA5F98);
  static const Color accentTeal = Color(0xFF262425); // brand black accent
  static const Color background = Color(0xFFFFFFFF); // pure white
  static const Color surface = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF262425); // brand black
  static const Color inkSoft = Color(0xFF54494B);
  static const Color inkMute = Color(0xFF9C8C90);
  // Thin/default lines are black-based; thick/emphasis lines use `primary`
  // (pink) throughout the app (see cardTheme, day_cell, buttons below).
  static const Color line = Color(0xFFD9D5D6);
  static const Color weekendBg = Color(0xFFF7F5F5);
  static const Color holidayBg = Color(0xFFF0EEEE);
  static const Color sun = Color(0xFFC4275F);
  static const Color sat = Color(0xFF262425);
  static const Color success = Color(0xFF2A9D8F);
  // Paid leave (有給) uses a light-blue accent instead of the usual pink,
  // so it stands out clearly from normal work-shift entries at a glance.
  static const Color paidLeave = Color(0xFF3FA9D6);
  static const Color paidLeaveBg = Color(0xFFE3F3FA);
}

class AppTheme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.line, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDeep,
          side: const BorderSide(color: AppColors.primary, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }
}
