import 'package:flutter/material.dart';

import '../theme/scrap_feedback.dart';
import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';
import 'torn_edge_clipper.dart';

enum PaperButtonVariant { primary, secondary, ghost, danger }

/// Paper chit button — presses flat into the desk instead of rippling.
class PaperButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PaperButtonVariant variant;
  final bool torn;
  final IconData? icon;
  final bool compact;
  final int seed;

  const PaperButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PaperButtonVariant.secondary,
    this.torn = false,
    this.icon,
    this.compact = false,
    this.seed = 7,
  });

  @override
  State<PaperButton> createState() => _PaperButtonState();
}

class _PaperButtonState extends State<PaperButton> {
  bool _pressed = false;

  Color get _fill {
    if (widget.onPressed == null) {
      return ScrapTheme.codeSurface;
    }
    return switch (widget.variant) {
      PaperButtonVariant.primary => ScrapTheme.accentSurface,
      PaperButtonVariant.secondary => ScrapTheme.cardSurface,
      PaperButtonVariant.ghost => Colors.transparent,
      PaperButtonVariant.danger => ScrapTheme.inkRed.withValues(alpha: 0.08),
    };
  }

  Color get _border {
    if (widget.onPressed == null) return ScrapTheme.dividers;
    return switch (widget.variant) {
      PaperButtonVariant.primary => ScrapTheme.accent.withValues(alpha: 0.45),
      PaperButtonVariant.secondary => ScrapTheme.dividers,
      PaperButtonVariant.ghost => Colors.transparent,
      PaperButtonVariant.danger => ScrapTheme.inkRed.withValues(alpha: 0.45),
    };
  }

  Color get _ink {
    if (widget.onPressed == null) return ScrapTheme.mutedText;
    return switch (widget.variant) {
      PaperButtonVariant.primary => ScrapTheme.accent,
      PaperButtonVariant.secondary => ScrapTheme.primaryText,
      PaperButtonVariant.ghost => ScrapTheme.accent,
      PaperButtonVariant.danger => ScrapTheme.inkRed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 9);

    Widget chit = AnimatedContainer(
      duration: ScrapMotion.press,
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(
        _pressed ? 2.0 : 0.0,
        _pressed ? 2.0 : 0.0,
        0,
      ),
      transformAlignment: Alignment.center,
      padding: pad,
      decoration: BoxDecoration(
        color: _pressed ? ScrapTheme.pressedSurface : _fill,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _border, width: 1),
        boxShadow: (_pressed || !enabled || widget.variant == PaperButtonVariant.ghost)
            ? const []
            : ScrapTheme.deskShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 14, color: _ink),
            const SizedBox(width: 6),
          ],
          Text(
            widget.label,
            style: ScrapTextStyles.stamp.copyWith(
              color: _ink,
              fontSize: widget.compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );

    if (widget.torn) {
      chit = Stack(
        clipBehavior: Clip.none,
        children: [
          chit,
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 8,
            child: IgnorePointer(
              child: CustomPaint(
                painter: TornEdgePainter(
                  seed: 7,
                  amplitude: 2.5,
                  fillColor: ScrapTheme.background,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                ScrapFeedback.tap();
                widget.onPressed!();
              }
            : null,
        child: chit,
      ),
    );
  }
}

/// Square icon chit — no splash circle, optional paper tooltip.
class PaperIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final double iconSize;

  const PaperIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.size = 36,
    this.iconSize = 20,
  });

  @override
  State<PaperIconButton> createState() => _PaperIconButtonState();
}

class _PaperIconButtonState extends State<PaperIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final ink = widget.color ?? ScrapTheme.secondaryText;

    Widget child = AnimatedContainer(
      duration: ScrapMotion.press,
      curve: Curves.easeOut,
      width: widget.size,
      height: widget.size,
      transform: Matrix4.translationValues(
        _pressed ? 1.5 : 0.0,
        _pressed ? 1.5 : 0.0,
        0,
      ),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pressed ? ScrapTheme.pressedSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusSmall),
        border: _pressed
            ? Border.all(color: ScrapTheme.dividers, width: 0.75)
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        widget.icon,
        size: widget.iconSize,
        color: enabled ? ink : ScrapTheme.mutedText,
      ),
    );

    child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                ScrapFeedback.tap();
                widget.onPressed!();
              }
            : null,
        child: child,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}
