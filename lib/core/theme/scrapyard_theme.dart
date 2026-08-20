import 'package:flutter/material.dart';

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
  static const Color inkRed = Color(0xFF9E4B3C); // Red pencil / danger ink
  static const Color pressedSurface = Color(0xFFECE8E2); // Chit pressed flat

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

  /// Hard contact shadow — chit lifted slightly off the desk.
  static const List<BoxShadow> deskShadow = [
    BoxShadow(
      color: Color(0x18000000),
      offset: Offset(2, 2),
      blurRadius: 0,
    ),
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
        error: inkRed,
      ),
      dividerTheme: const DividerThemeData(
        color: dividers,
        thickness: 1,
        space: 1,
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: accent.withValues(alpha: 0.04),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        showDuration: const Duration(seconds: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: tape,
          borderRadius: BorderRadius.circular(borderRadiusSmall),
          border: Border.all(color: kraft.withValues(alpha: 0.85), width: 0.75),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              offset: Offset(1, 1),
              blurRadius: 0,
            ),
          ],
        ),
        textStyle: ScrapTextStyles.stamp.copyWith(
          color: primaryText,
          fontSize: 10,
          letterSpacing: 1.0,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: dividers,
        thumbColor: cardSurface,
        overlayColor: Colors.transparent,
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: 7,
          elevation: 0,
          pressedElevation: 0,
        ),
        trackShape: RectangularSliderTrackShape(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: accent,
        contentTextStyle: ScrapTextStyles.stamp.copyWith(
          color: cardSurface,
          letterSpacing: 1.0,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusSmall),
        ),
        elevation: 0,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: secondaryText,
          highlightColor: Colors.transparent,
          hoverColor: accent.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusSmall),
          ),
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadiusSmall),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: ScrapTextStyles.stamp,
        ),
      ),
      useMaterial3: true,
    );
  }
}

class ScrapTextStyles {
  static const String _sans = 'Noto Sans';
  static const String _serif = 'Courier Prime';

  static TextTheme get textTheme {
    return const TextTheme().copyWith(
      displayLarge: display,
      titleLarge: heading,
      bodyLarge: body,
      bodyMedium: caption,
      labelLarge: label,
    );
  }

  static TextStyle get display => const TextStyle(
        fontFamily: _serif,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: ScrapTheme.primaryText,
        letterSpacing: -0.5,
      );

  static TextStyle get heading => const TextStyle(
        fontFamily: _serif,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: ScrapTheme.primaryText,
        letterSpacing: -0.2,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: _sans,
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: ScrapTheme.bodyText,
        height: 1.5,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: _sans,
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: ScrapTheme.secondaryText,
        height: 1.4,
      );

  static TextStyle get label => const TextStyle(
        fontFamily: _sans,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: ScrapTheme.mutedText,
        letterSpacing: 0.5,
      );

  /// Typewriter stamp style for filing tags and ⟨ ⟩ chrome.
  static TextStyle get stamp => const TextStyle(
        fontFamily: _serif,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: ScrapTheme.accent,
        letterSpacing: 1.4,
      );
}
