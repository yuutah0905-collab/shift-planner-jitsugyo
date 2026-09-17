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
  // Moderate (not-too-dark) gray for holiday/off-day columns in the
  // monthly shift matrix - dark enough to stay clearly visible even when
  // printed in monochrome, but light enough that black text on top of it
  // still reads comfortably.
  static const Color holidayGray = Color(0xFFD9D9D9);
  // Dedicated grid-line color for the monthly shift matrix table (both
  // on-screen and PDF). Deliberately a bit darker than `line` above -
  // `line` (0xFFD9D5D6) is nearly the same brightness as `holidayGray`
  // (0xFFD9D9D9) and the light-blue paid-leave fill, so borders drawn in
  // `line` become almost invisible once most cells got colored fills
  // (gray for days off, light blue for paid leave). This stays a thin,
  // subtle grid line but with enough contrast to stay visible on every
  // cell background.
  static const Color gridLine = Color(0xFFBFBBBC);
  static const Color sun = Color(0xFFC4275F);
  static const Color sat = Color(0xFF262425);
  static const Color success = Color(0xFF2A9D8F);
  // Paid leave (有給) uses a light-blue accent instead of the usual pink,
  // so it stands out clearly from normal work-shift entries at a glance.
  static const Color paidLeave = Color(0xFF3FA9D6);
  static const Color paidLeaveBg = Color(0xFFE3F3FA);
  // A day with a free-form dial-picker time range (doesn't match any
  // fixed A~Y code) uses a distinct yellow, so both staff (day_cell) and
  // admin (monthly shift matrix) recognize it at a glance as needing a
  // closer look via its detail popup, rather than a normal fixed-code
  // shift.
  static const Color customTime = Color(0xFFC9A227);
  static const Color customTimeBg = Color(0xFFFFF6D8);
  // Stronger, more saturated yellow used specifically for the admin's
  // monthly shift matrix cell fill (vs. the softer customTimeBg tint
  // used behind the small badge on the staff-facing day_cell) - matches
  // the "セルを黄色にして" request so it reads as an unambiguous yellow
  // cell at a glance across the whole matrix.
  static const Color customTimeCell = Color(0xFFFFEB3B);
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
      // Explicitly bundle a Japanese-glyph font so kanji render with proper
      // Japanese (not Chinese) glyph shapes on every platform. Without this,
      // Roboto has no CJK glyphs and the renderer silently falls back to
      // whatever CJK font happens to be available, which can be a
      // Simplified/Traditional Chinese font with different kanji shapes
      // (e.g. 直/花/辻 look subtly different).
      fontFamily: 'NotoSansJP',
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
