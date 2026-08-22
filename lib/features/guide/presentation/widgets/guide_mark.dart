import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/toolbar_tool_icons.dart';
import '../../domain/guide_content.dart';

/// Renders a toolbar-accurate mark, or a Material icon when the UI has one.
class GuideMark extends StatelessWidget {
  final IconData? icon;
  final GuideGlyph? glyph;
  final double size;
  final Color color;

  const GuideMark({
    super.key,
    this.icon,
    this.glyph,
    this.size = 20,
    this.color = ScrapTheme.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (glyph == GuideGlyph.spark) {
      return Text(
        '✦',
        style: ScrapTextStyles.body.copyWith(
          fontSize: size * 0.9,
          height: 1,
          color: color,
        ),
      );
    }
    if (glyph == GuideGlyph.highlighter) {
      return HighlighterIcon(size: size, color: color);
    }
    if (glyph == GuideGlyph.eraser) {
      return EraserIcon(size: size, color: color);
    }
    if (glyph == GuideGlyph.lasso) {
      return LassoIcon(size: size, color: color);
    }
    if (icon != null) {
      return Icon(icon, size: size, color: color);
    }
    return const SizedBox.shrink();
  }
}
