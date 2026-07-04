import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for Mushi Player.
///
/// The whole app leans on a small, deliberate palette and a single typographic
/// scale so every screen feels like part of the same product. Screens layer a
/// dynamic, artwork-driven gradient on top of these neutral defaults.
class AppTheme {
  AppTheme._();

  // Brand + neutrals ---------------------------------------------------------
  static const Color accent = Color(0xFF8B7CFF);
  static const Color accentSoft = Color(0xFFB6ADFF);

  static const Color ink = Color(0xFF0B0B10); // deepest background
  static const Color surface = Color(0xFF15151C); // cards / sheets
  static const Color surfaceHigh = Color(0xFF1E1E27);

  static const Color textPrimary = Color(0xFFF6F5FB);
  static const Color textSecondary = Color(0xFFB4B2C4);
  static const Color textTertiary = Color(0xFF7E7C90);

  static const Color favorite = Color(0xFFFF5C7A);

  /// Neutral fallback gradient used before artwork colors are ready.
  static const List<Color> fallbackGradient = [
    Color(0xFF23222E),
    Color(0xFF141319),
    Color(0xFF0B0B10),
  ];

  static ThemeData build() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
    );

    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
