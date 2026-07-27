import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScrapTheme {
  // Colour Palette
  static const Color background = Color(0xFFF5F4F0); // Scrap paper
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color primaryText = Color(0xFF1C1C1C); // Fountain pen black
  static const Color bodyText = Color(0xFF3A3835); // Softer ink
  static const Color secondaryText = Color(0xFF4A4A4A); // Pencil grey
  static const Color mutedText = Color(0xFF9A9590); // Light pencil
  static const Color accent = Color(0xFF6B4C3B); // Warm modern brown
  static const Color accentSurface = Color(0xFFF0EAE5); // Pale brown tint
  static const Color dividers = Color(0xFFE0DDD8); // Warm eraser-grey
  static const Color codeSurface = Color(0xFFEDEAE4); // Slightly darker paper
  static const Color notebookLines = Color(0xFFEBE8E2); // Rule lines on canvas
  static const Color kraft = Color(0xFFD9CDBA); // Stacked sheet backs
  static const Color tape = Color(0xFFE8DCC8); // Stamp outlines / label chrome

  // Border Radius
  static const double borderRadiusDefault = 4.0;
  static const double borderRadiusSmall = 2.0;

  // Custom Box Shadow (no harsh shadows)
  static const List<BoxShadow> subtleShadow = [
    BoxShadow(
      color: Color(0x04000000), // 4% black
      offset: Offset(0, 4),
      blurRadius: 16,
    )
  ];

  // ThemeData
  static ThemeData get themeData {
    return ThemeData(
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      textTheme: ScrapTextStyles.textTheme,
      colorScheme: const ColorScheme.light(
        primary: accent,
        surface: background,
        onSurface: primaryText,
      ),
      dividerTheme: const DividerThemeData(
        color: dividers,
        thickness: 1,
        space: 1,
      ),
      useMaterial3: true,
    );
  }
}

class ScrapTextStyles {
  static TextTheme get textTheme {
    return GoogleFonts.notoSansTextTheme().copyWith(
      displayLarge: display,
      titleLarge: heading,
      bodyLarge: body,
      bodyMedium: caption,
      labelLarge: label,
    );
  }

  static TextStyle get display => GoogleFonts.libreBaskerville(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: ScrapTheme.primaryText,
        letterSpacing: -0.5,
      );

  static TextStyle get heading => GoogleFonts.libreBaskerville(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: ScrapTheme.primaryText,
        letterSpacing: -0.2,
      );

  static TextStyle get body => GoogleFonts.notoSans(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: ScrapTheme.bodyText,
        height: 1.5,
      );

  static TextStyle get caption => GoogleFonts.notoSans(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: ScrapTheme.secondaryText,
        height: 1.4,
      );

  static TextStyle get label => GoogleFonts.notoSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: ScrapTheme.mutedText,
        letterSpacing: 0.5,
      );

  /// Typewriter stamp style for filing tags and ⟨ ⟩ chrome.
  static TextStyle get stamp => GoogleFonts.courierPrime(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: ScrapTheme.accent,
        letterSpacing: 1.4,
      );
}
