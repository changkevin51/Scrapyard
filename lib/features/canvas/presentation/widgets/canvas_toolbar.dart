import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../data/pen_engine.dart';
import '../providers/canvas_providers.dart';
import '../providers/canvas_viewport_provider.dart';
import 'canvas_smart_widgets.dart';
import 'pen_settings_panel.dart';
import 'shape_library_panel.dart';
import 'sticker_library.dart';

// ─────────────────────────────────────────────────────────
// Tool definition — each tool has an icon, short label & tip
// ─────────────────────────────────────────────────────────
typedef _ToolDef = ({
  IconData icon,
  String label,
  String tip,
  CanvasTool tool,
});

const List<_ToolDef> _tools = [
  (icon: Icons.edit_outlined,      label: 'Pen',   tip: 'Pen',          tool: CanvasTool.pen),
  (icon: Icons.brush_outlined,     label: 'Brush', tip: 'Brush',        tool: CanvasTool.brush),
  (icon: Icons.highlight_outlined, label: 'Highlighter', tip: 'Highlighter',  tool: CanvasTool.highlighter), // icon unused — custom glyph
  (icon: Icons.auto_fix_off_outlined, label: 'Erase', tip: 'Eraser', tool: CanvasTool.eraser), // icon unused — custom glyph
  (icon: Icons.horizontal_rule,    label: 'Line',  tip: 'Straight line', tool: CanvasTool.straightLine),
  (icon: Icons.text_fields_outlined, label: 'Text', tip: 'Text',       tool: CanvasTool.text),
  (icon: Icons.category_outlined,  label: 'Shape', tip: 'Shape',        tool: CanvasTool.shape),
  (icon: Icons.gesture,            label: 'Lasso', tip: 'Lasso',       tool: CanvasTool.lasso), // icon unused — custom glyph
  (icon: Icons.auto_awesome,       label: 'Smelt', tip: 'Smelt',       tool: CanvasTool.smelt),
];

// ─────────────────────────────────────────────────────────
// Shared press scale — same feel as home _ScrapPressable
// ─────────────────────────────────────────────────────────
class _ToolPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ToolPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_ToolPressable> createState() => _ToolPressableState();
}

class _ToolPressableState extends State<_ToolPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null || widget.onLongPress != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.onTap != null) {
          ScrapFeedback.tap();
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _pressed = false),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: ScrapMotion.press,
        curve: ScrapMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Main toolbar widget
// ─────────────────────────────────────────────────────────
class CanvasToolbar extends ConsumerWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPenMode    = ref.watch(isPenModeActiveProvider);
    final position     = ref.watch(toolbarPositionProvider);
    final strokeStyle  = ref.watch(strokeStyleProvider);
    final palette      = ref.watch(inkPaletteProvider);
    final isHorizontal = position == ToolbarPosition.top || position == ToolbarPosition.bottom;

    final children = <Widget>[
      // ── Draw / Scroll mode toggle ──────────────────────
      _ModeToggle(isPenMode: isPenMode),
      _sep(isHorizontal),

      // ── All drawing tools – always exposed ─────────────
      for (final t in _tools)
        _ToolButton(def: t),
      const PenSettingsButton(),
      // Sticker library button
      const _StickerButton(),
      _sep(isHorizontal),

      // ── Stroke style chips – inline ────────────────────
      for (final s in StrokeStyle.values)
        _StrokeStyleChip(style: s, current: strokeStyle),
      _sep(isHorizontal),

      // ── Undo / Redo ────────────────────────────────────
      const _ActionButton(
          icon: Icons.undo_outlined, tip: 'Undo',
          action: CanvasTool.undo),
      const _ActionButton(
          icon: Icons.redo_outlined, tip: 'Redo',
          action: CanvasTool.redo),
      _sep(isHorizontal),

      // ── Colour palette ─────────────────────────────────
      for (var i = 0; i < palette.length; i++)
        _ColorDot(color: palette[i], index: i),
      _sep(isHorizontal),

      // ── Thickness dots ──────────────────────────────────
      const _ThicknessDots(),
      _sep(isHorizontal),

      // ── Settings sheet ─────────────────────────────────
      const _SettingsButton(),
    ];

    // Tape hairline on the canvas-facing edge
    BorderSide tapeEdge = BorderSide.none;
    BorderSide dividerEdge = BorderSide.none;
    if (isHorizontal) {
      if (position == ToolbarPosition.top) {
        tapeEdge = const BorderSide(color: ScrapTheme.tape, width: 1);
        dividerEdge = const BorderSide(color: ScrapTheme.dividers, width: 0.5);
      } else {
        tapeEdge = const BorderSide(color: ScrapTheme.tape, width: 1);
        dividerEdge = const BorderSide(color: ScrapTheme.dividers, width: 0.5);
      }
    } else {
      tapeEdge = const BorderSide(color: ScrapTheme.tape, width: 1);
      dividerEdge = const BorderSide(color: ScrapTheme.dividers, width: 0.5);
    }

    return Container(
      width: isHorizontal ? double.infinity : null,
      height: isHorizontal ? null : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        border: isHorizontal
            ? Border(
                bottom: position == ToolbarPosition.top ? tapeEdge : BorderSide.none,
                top: position == ToolbarPosition.bottom ? tapeEdge : BorderSide.none,
              )
            : Border(
                right: position == ToolbarPosition.left ? tapeEdge : BorderSide.none,
                left: position == ToolbarPosition.right ? tapeEdge : BorderSide.none,
              ),
      ),
      foregroundDecoration: isHorizontal
          ? BoxDecoration(
              border: Border(
                bottom: position == ToolbarPosition.top ? dividerEdge : BorderSide.none,
                top: position == ToolbarPosition.bottom ? dividerEdge : BorderSide.none,
              ),
            )
          : BoxDecoration(
              border: Border(
                right: position == ToolbarPosition.left ? dividerEdge : BorderSide.none,
                left: position == ToolbarPosition.right ? dividerEdge : BorderSide.none,
              ),
            ),
      child: SingleChildScrollView(
        scrollDirection: isHorizontal ? Axis.horizontal : Axis.vertical,
        child: isHorizontal
            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: children)
            : Column(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }

  Widget _sep(bool isHorizontal) => isHorizontal
      ? Container(
          width: 1,
          height: 16,
          color: ScrapTheme.tape.withValues(alpha: 0.7),
          margin: const EdgeInsets.symmetric(horizontal: 6),
        )
      : Container(
          height: 1,
          width: 16,
          color: ScrapTheme.tape.withValues(alpha: 0.7),
          margin: const EdgeInsets.symmetric(vertical: 6),
        );
}

// ─────────────────────────────────────────────────────────
// Draw / Scroll mode toggle
// ─────────────────────────────────────────────────────────
class _ModeToggle extends ConsumerWidget {
  final bool isPenMode;
  const _ModeToggle({required this.isPenMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isPenMode ? 'Switch to scroll/read mode' : 'Switch to draw mode',
      child: _ToolPressable(
        onTap: () {
          final newMode = !isPenMode;
          ref.read(isPenModeActiveProvider.notifier).state = newMode;
          final tool = ref.read(activeCanvasToolProvider);
          if (!newMode && (tool == CanvasTool.lasso || tool == CanvasTool.smelt)) {
            ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.pen;
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPenMode
                ? ScrapTheme.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            isPenMode ? Icons.edit_outlined : Icons.pan_tool_alt_outlined,
            size: 22,
            color: isPenMode ? ScrapTheme.accent : ScrapTheme.mutedText,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tool button (icon or label based on mode)
// Shape tool supports long-press to open the shape library.
// ─────────────────────────────────────────────────────────────────
class _ToolButton extends ConsumerWidget {
  final _ToolDef def;
  const _ToolButton({required this.def});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTool    = ref.watch(activeCanvasToolProvider);
    final isActive      = activeTool == def.tool;
    final libraryShape  = ref.watch(selectedLibraryShapeProvider);
    final hasLibShape   = def.tool == CanvasTool.shape && libraryShape != null;

    return Tooltip(
      message: def.tool == CanvasTool.shape
          ? '${def.tip} (long‑press for library)'
          : def.tip,
      child: _ToolPressable(
        onTap: () {
          ref.read(activeCanvasToolProvider.notifier).state = def.tool;
          ref.read(isPenModeActiveProvider.notifier).state = true;
          if (def.tool == CanvasTool.pen) {
            ref.read(activeInkFamilyProvider.notifier).state = InkFamily.pen;
            final settings = ref.read(penSettingsProvider);
            if (settings.penStyle.family != InkFamily.pen) {
              ref.read(penSettingsProvider.notifier).state =
                  settings.copyWith(penStyle: PenStyle.pen);
            }
            restoreToolColor(ref, CanvasTool.pen);
          } else if (def.tool == CanvasTool.brush) {
            ref.read(activeInkFamilyProvider.notifier).state = InkFamily.brush;
            final settings = ref.read(penSettingsProvider);
            if (settings.penStyle.family != InkFamily.brush) {
              ref.read(penSettingsProvider.notifier).state =
                  settings.copyWith(penStyle: PenStyle.calligraphy);
            }
            restoreToolColor(ref, CanvasTool.brush);
          } else if (def.tool == CanvasTool.highlighter) {
            ref.read(activeInkFamilyProvider.notifier).state =
                InkFamily.highlighter;
            restoreToolColor(ref, CanvasTool.highlighter);
          }
        },
        onLongPress: def.tool == CanvasTool.shape
            ? () => showShapeLibrary(context)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? ScrapTheme.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolGlyph(
                    def,
                    size: 22,
                    color: isActive ? ScrapTheme.accent : ScrapTheme.secondaryText,
                  ),
                  // Highlighter-swipe underline under active tool
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(top: 2),
                    height: 2,
                    width: isActive ? 18 : 0,
                    decoration: BoxDecoration(
                      color: ScrapTheme.accent.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
              if (hasLibShape)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                      color: ScrapTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _toolGlyph(_ToolDef def, {required double size, required Color color}) {
  if (def.tool == CanvasTool.eraser) {
    return _EraserIcon(size: size, color: color);
  }
  if (def.tool == CanvasTool.highlighter) {
    return _HighlighterIcon(size: size, color: color);
  }
  if (def.tool == CanvasTool.lasso) {
    return _LassoIcon(size: size, color: color);
  }
  return Icon(def.icon, size: size, color: color);
}

/// Rectangular selection marquee — rounded square with a dashed outline.
class _LassoIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _LassoIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LassoIconPainter(color)),
    );
  }
}

class _LassoIconPainter extends CustomPainter {
  final Color color;
  const _LassoIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.12, h * 0.16, w * 0.88, h * 0.84),
        Radius.circular(w * 0.18),
      ));

    // March along the outline, drawing dash / gap segments.
    final dash = w * 0.17;
    final gap = w * 0.11;
    for (final metric in outline.computeMetrics()) {
      double dist = dash * 0.5;
      while (dist < metric.length) {
        final end = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LassoIconPainter old) => old.color != color;
}

/// Chisel-tip highlighter marker — fat barrel, slanted nib.
class _HighlighterIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _HighlighterIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HighlighterIconPainter(color)),
    );
  }
}

class _HighlighterIconPainter extends CustomPainter {
  final Color color;
  const _HighlighterIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Marker @ ~45°, nib pointing bottom-left.
    // Chisel nib — shaded wedge with the signature slanted cut.
    final nib = Path()
      ..moveTo(w * 0.171, h * 0.671)
      ..lineTo(w * 0.270, h * 0.770)
      ..lineTo(w * 0.157, h * 0.883)
      ..lineTo(w * 0.128, h * 0.714)
      ..close();
    canvas.drawPath(
      nib,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(nib, stroke);

    // Fat barrel — noticeably chunkier than the pencil, no eraser.
    final barrel = Path()
      ..moveTo(w * 0.667, h * 0.047)
      ..lineTo(w * 0.893, h * 0.273)
      ..lineTo(w * 0.493, h * 0.673)
      ..lineTo(w * 0.267, h * 0.447)
      ..close();
    canvas.drawPath(barrel, stroke);

    // Neck — taper from barrel down to the nib.
    canvas.drawLine(
        Offset(w * 0.267, h * 0.447), Offset(w * 0.171, h * 0.671), stroke);
    canvas.drawLine(
        Offset(w * 0.493, h * 0.673), Offset(w * 0.270, h * 0.770), stroke);
  }

  @override
  bool shouldRepaint(covariant _HighlighterIconPainter old) =>
      old.color != color;
}

/// Classic angled rubber eraser — outlined to match other toolbar tools.
class _EraserIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _EraserIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EraserIconPainter(color)),
    );
  }
}

class _EraserIconPainter extends CustomPainter {
  final Color color;
  const _EraserIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Angled eraser body (parallelogram).
    // Corners: tip (top), then clockwise — A tip-left, B tip-right, C base-right, D base-left.
    final a = Offset(w * 0.52, h * 0.16);
    final b = Offset(w * 0.84, h * 0.30);
    final c = Offset(w * 0.50, h * 0.84);
    final d = Offset(w * 0.18, h * 0.70);

    // Split a bit above center so the shaded rubber reads larger.
    final midLeft = Offset.lerp(a, d, 0.38)!;
    final midRight = Offset.lerp(b, c, 0.38)!;

    // Shade the bottom half (eraser rubber).
    final shade = Path()
      ..moveTo(midLeft.dx, midLeft.dy)
      ..lineTo(midRight.dx, midRight.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(
      shade,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );

    final body = Path()
      ..moveTo(d.dx, d.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(body, stroke);

    // Ferrule / band across the midpoint.
    canvas.drawLine(midLeft, midRight, stroke..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _EraserIconPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────
// Stroke style inline chips  ─ Solid / Dotted / Dashed
// ─────────────────────────────────────────────────────────
class _StrokeStyleChip extends ConsumerWidget {
  final StrokeStyle style;
  final StrokeStyle current;
  const _StrokeStyleChip({required this.style, required this.current});

  static const _labels = {
    StrokeStyle.solid:  '—',
    StrokeStyle.dotted: '···',
    StrokeStyle.dashed: '- -',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = style == current;
    return Tooltip(
      message: style.name[0].toUpperCase() + style.name.substring(1),
      child: _ToolPressable(
        onTap: () => ref.read(strokeStyleProvider.notifier).state = style,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? ScrapTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? ScrapTheme.accent.withValues(alpha: 0.35)
                  : ScrapTheme.dividers,
              width: 1,
            ),
          ),
          child: Text(
            _labels[style]!,
            style: ScrapTextStyles.label.copyWith(
              fontSize: 13,
              letterSpacing: 1.5,
              color: isActive ? ScrapTheme.accent : ScrapTheme.secondaryText,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Action button (Undo / Redo)
// ─────────────────────────────────────────────────────────
class _ActionButton extends ConsumerWidget {
  final IconData icon;
  final String tip;
  final CanvasTool action;
  const _ActionButton(
      {required this.icon, required this.tip,
       required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: tip,
      child: _ToolPressable(
        onTap: () {
          if (action == CanvasTool.undo) ref.read(strokesProvider.notifier).undo();
          if (action == CanvasTool.redo) ref.read(strokesProvider.notifier).redo();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(icon, size: 20, color: ScrapTheme.secondaryText),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Colour dots — ink-well ring, no blur glow
// Palm rejection on: pen tap selects colour; finger tap opens picker.
// Palm rejection off: single tap selects; double tap opens picker.
// Custom picks rewrite this slot so the toolbar icon updates.
// ─────────────────────────────────────────────────────────
class _ColorDot extends ConsumerStatefulWidget {
  final Color color;
  final int index;
  const _ColorDot({required this.color, required this.index});

  @override
  ConsumerState<_ColorDot> createState() => _ColorDotState();
}

class _ColorDotState extends ConsumerState<_ColorDot> {
  bool _pressed = false;
  PointerDeviceKind? _pointerKind;

  static bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _selectColor() {
    applyInkColor(ref, widget.color, paletteIndex: widget.index);
  }

  void _openPicker() {
    showInkColorPicker(
      context,
      initialColor: widget.color,
      paletteIndex: widget.index,
    );
  }

  void _onTap() {
    _selectColor();
    final palmReject = ref.read(stylusOnlyModeProvider);
    if (palmReject && !_isStylus(_pointerKind ?? PointerDeviceKind.touch)) {
      _openPicker();
    }
    ScrapFeedback.tap();
  }

  void _onDoubleTap() {
    _selectColor();
    _openPicker();
    ScrapFeedback.tap();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(paletteIndexProvider);
    final isSelected = selectedIndex == widget.index;
    final palmReject = ref.watch(stylusOnlyModeProvider);

    return Tooltip(
      message: 'Ink colour',
      child: Listener(
        onPointerDown: (e) {
          _pointerKind = e.kind;
          setState(() => _pressed = true);
        },
        child: GestureDetector(
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _onTap,
          onDoubleTap: palmReject ? null : _onDoubleTap,
          child: AnimatedScale(
            scale: _pressed ? 0.93 : 1.0,
            duration: ScrapMotion.press,
            curve: ScrapMotion.pressCurve,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: ScrapTheme.accent, width: 1.5)
                    : Border.all(color: Colors.transparent, width: 1.5),
              ),
              padding: const EdgeInsets.all(2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Ink colour picker — scrap dialog wrapping flutter_colorpicker
// ─────────────────────────────────────────────────────────
Future<void> showInkColorPicker(
  BuildContext context, {
  required Color initialColor,
  required int paletteIndex,
}) {
  return showScrapDialog(
    context: context,
    builder: (_) => _InkColorPickerDialog(
      initialColor: initialColor,
      paletteIndex: paletteIndex,
    ),
  );
}

class _InkColorPickerDialog extends ConsumerStatefulWidget {
  final Color initialColor;
  final int paletteIndex;
  const _InkColorPickerDialog({
    required this.initialColor,
    required this.paletteIndex,
  });

  @override
  ConsumerState<_InkColorPickerDialog> createState() =>
      _InkColorPickerDialogState();
}

class _InkColorPickerDialogState
    extends ConsumerState<_InkColorPickerDialog> {
  late Color _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialColor.withValues(alpha: 1.0);
  }

  void _apply() {
    applyInkColor(
      ref,
      _picked,
      paletteIndex: widget.paletteIndex,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScrapStampLabel(text: '⟨ Ink ⟩'),
          const SizedBox(height: 8),
          Text(
            'Pick Colour',
            style: ScrapTextStyles.heading.copyWith(fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.copyWith(
                  bodyLarge: ScrapTextStyles.body.copyWith(fontSize: 13),
                  bodyMedium: ScrapTextStyles.caption.copyWith(fontSize: 12),
                ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: ScrapTheme.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintStyle: ScrapTextStyles.caption
                  .copyWith(color: ScrapTheme.mutedText),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                borderSide: const BorderSide(color: ScrapTheme.dividers),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                borderSide: const BorderSide(
                  color: ScrapTheme.accent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPicker(
                pickerColor: _picked,
                onColorChanged: (c) => setState(() => _picked = c),
                enableAlpha: false,
                hexInputBar: true,
                portraitOnly: true,
                labelTypes: const [],
                pickerAreaHeightPercent: 0.72,
                pickerAreaBorderRadius: BorderRadius.circular(
                  ScrapTheme.borderRadiusDefault,
                ),
                displayThumbColor: true,
              ),
              const SizedBox(height: 4),
              // Preset ink swatches — same palette as the toolbar
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'PRESETS',
                  style: ScrapTextStyles.stamp.copyWith(fontSize: 10),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in defaultInkPalette)
                    GestureDetector(
                      onTap: () => setState(() => _picked = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _picked.toARGB32() == c.toARGB32()
                                ? ScrapTheme.accent
                                : ScrapTheme.dividers,
                            width: _picked.toARGB32() == c.toARGB32()
                                ? 2
                                : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Live preview chip
              Row(
                children: [
                  Text('PREVIEW',
                      style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _picked,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: ScrapTheme.dividers),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText),
          ),
        ),
        GestureDetector(
          onTap: _apply,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: ScrapTheme.accent,
              borderRadius:
                  BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            ),
            child: Text(
              'Use Colour',
              style: ScrapTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Thickness dot-size selector
// ─────────────────────────────────────────────────────────
class _ThicknessDots extends ConsumerWidget {
  const _ThicknessDots();

  static const _sizes = [(8.0, 0.5), (12.0, 1.0), (16.0, 2.0), (20.0, 3.0)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mod = ref.watch(strokeWidthModifierProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final (size, val) in _sizes)
          _ToolPressable(
            onTap: () => ref.read(strokeWidthModifierProvider.notifier).state = val,
            child: Tooltip(
              message: 'Thickness $val×',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: (mod - val).abs() < 0.3
                      ? ScrapTheme.accent
                      : ScrapTheme.dividers,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Settings button  →  opens bottom sheet
// ─────────────────────────────────────────────────────────
class _SettingsButton extends ConsumerWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: 'Canvas settings',
      child: _ToolPressable(
        onTap: () => _showSettings(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(Icons.tune_outlined, size: 22, color: ScrapTheme.mutedText),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showScrapSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ScrapTheme.cardSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ScrapTheme.borderRadiusDefault))),
      builder: (_) => const _CanvasSettingsSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Settings bottom sheet  (layout / dock / palm rejection)
// ─────────────────────────────────────────────────────────
class _CanvasSettingsSheet extends ConsumerWidget {
  const _CanvasSettingsSheet();

  Future<void> _onPageStyleTap(
    BuildContext context,
    WidgetRef ref,
    PageLayout current,
    PageLayout next,
  ) async {
    if (next == current) return;
    if (current.isInfinite) return; // locked

    if (next.isInfinite) {
      final confirmed = await showScrapDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ScrapTheme.cardSurface,
          title: Text('Switch to Infinite?', style: ScrapTextStyles.heading),
          content: Text(
            'Once enabled, you cannot convert this note back to Plain, Ruled, '
            'Dotted, or Grid. Pan and zoom freely on an unbounded canvas.',
            style: ScrapTextStyles.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: ScrapTextStyles.body),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Enable Infinite',
                style: ScrapTextStyles.body.copyWith(color: ScrapTheme.accent),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(pageLayoutProvider.notifier).convertToInfinite();
      }
      return;
    }

    await ref.read(pageLayoutProvider.notifier).setFinite(next);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(pageLayoutProvider);
    final pos = ref.watch(toolbarPositionProvider);
    final palmReject = ref.watch(stylusOnlyModeProvider);
    final lockedInfinite = layout.isInfinite;

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grabber
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ScrapTheme.kraft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const ScrapStampLabel(text: '⟨ Canvas ⟩'),
            const SizedBox(height: 8),
            Text('Canvas Settings',
                style: ScrapTextStyles.heading.copyWith(fontSize: 18)),
            const SizedBox(height: 24),

            // Insert tools (relocated from the ✦ FAB)
            Text('INSERT', style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    showInsertTableDialog(context);
                  },
                  child: _chip('TABLE', false),
                ),
                if (ref.watch(ocrResultsProvider).isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      final texts = ref
                          .read(ocrResultsProvider)
                          .map((r) => r.text)
                          .toList();
                      Navigator.pop(context);
                      convertOcrToTextNode(
                        ref,
                        context,
                        ocrTexts: texts,
                        ocrStrokeIds: const [],
                      );
                    },
                    child: _chip('HANDWRITING → TEXT', false),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Page layout
            Text('PAGE STYLE',
                style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PageLayout.values.map((l) {
                final sel = l == layout;
                final disabled = lockedInfinite && l.isFinite;
                return Opacity(
                  opacity: disabled ? 0.4 : 1,
                  child: GestureDetector(
                    onTap: disabled
                        ? null
                        : () => _onPageStyleTap(context, ref, layout, l),
                    child: _chip(l.chipLabel, sel),
                  ),
                );
              }).toList(),
            ),
            if (lockedInfinite) ...[
              const SizedBox(height: 8),
              Text(
                'Infinite is locked for this note — other page styles are disabled.',
                style: ScrapTextStyles.caption
                    .copyWith(color: ScrapTheme.mutedText),
              ),
            ],
            const SizedBox(height: 20),

            // Go Home — infinite only
            Text('VIEWPORT',
                style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            Opacity(
              opacity: lockedInfinite ? 1 : 0.4,
              child: GestureDetector(
                onTap: lockedInfinite
                    ? () {
                        ScrapFeedback.tap();
                        ref.read(canvasViewportProvider.notifier).goHome();
                        Navigator.pop(context);
                      }
                    : null,
                child: _chip('GO HOME', false),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lockedInfinite
                  ? 'Jump to your first stroke (home anchor).'
                  : 'Available only in Infinite page style.',
              style: ScrapTextStyles.caption
                  .copyWith(color: ScrapTheme.mutedText),
            ),
            const SizedBox(height: 20),

            // Toolbar dock
            Text('TOOLBAR POSITION',
                style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ToolbarPosition.values.map((p) {
                final sel = p == pos;
                return GestureDetector(
                  onTap: () {
                    ref.read(toolbarPositionProvider.notifier).state = p;
                    Navigator.pop(context);
                  },
                  child: _chip(p.name.toUpperCase(), sel),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Palm rejection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PALM REJECTION',
                      style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
                  Text('Touch = scroll/zoom, Stylus = write',
                      style: ScrapTextStyles.caption
                          .copyWith(color: ScrapTheme.mutedText)),
                ]),
                PaperSwitch(
                  value: palmReject,
                  onChanged: (v) =>
                      ref.read(stylusOnlyModeProvider.notifier).state = v,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? ScrapTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: selected ? ScrapTheme.accent : ScrapTheme.dividers),
        ),
        child: Text(
          label,
          style: ScrapTextStyles.stamp.copyWith(
            fontSize: 11,
            color: selected ? Colors.white : ScrapTheme.secondaryText,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
// Sticker library toolbar button
// ─────────────────────────────────────────────────────────────────
class _StickerButton extends StatelessWidget {
  const _StickerButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sticker library',
      child: _ToolPressable(
        onTap: () => showStickerLibrary(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(Icons.emoji_emotions_outlined, size: 20,
              color: ScrapTheme.mutedText),
        ),
      ),
    );
  }
}
