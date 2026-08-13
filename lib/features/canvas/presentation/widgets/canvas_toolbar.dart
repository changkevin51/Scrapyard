import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/toolbar_tool_icons.dart';
import '../../data/pen_engine.dart';
import '../providers/canvas_providers.dart';
import '../providers/canvas_viewport_provider.dart';
import 'canvas_smart_widgets.dart';
import 'ink_color_controls.dart';
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
    final palette      = ref.watch(inkPaletteProvider);
    final isHorizontal = position == ToolbarPosition.top || position == ToolbarPosition.bottom;

    final centeredChildren = <Widget>[
      _sep(isHorizontal),

      // ── All drawing tools – always exposed ─────────────
      for (final t in _tools)
        _ToolButton(def: t),
      const PenSettingsButton(),
      // Sticker library button
      const _StickerButton(),
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
        InkColorDot(color: palette[i], index: i),
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
      child: isHorizontal
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ModeToggle(isPenMode: isPenMode),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minWidth: constraints.maxWidth),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: centeredChildren,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ModeToggle(isPenMode: isPenMode),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: centeredChildren,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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
    return EraserIcon(size: size, color: color);
  }
  if (def.tool == CanvasTool.highlighter) {
    return HighlighterIcon(size: size, color: color);
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

// Action button (Undo / Redo)
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
          if (action == CanvasTool.undo) undoCanvas(ref);
          if (action == CanvasTool.redo) redoCanvas(ref);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Icon(icon, size: 20, color: ScrapTheme.secondaryText),
        ),
      ),
    );
  }
}

// ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ
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
    PageCanvasConfig current,
    PageLayout style,
  ) async {
    if (style == current.style) return;
    await ref.read(pageLayoutProvider.notifier).setStyle(style);
  }

  Future<void> _onInfiniteTap(
    BuildContext context,
    WidgetRef ref,
    PageCanvasConfig current,
  ) async {
    if (current.isInfinite) return; // already locked on

    final confirmed = await showScrapDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ScrapTheme.cardSurface,
        title: Text('Switch to Infinite?', style: ScrapTextStyles.heading),
        content: Text(
          'Once enabled, you cannot return this note to a fixed page size. '
          'You can still change the background style (Plain, Ruled, Dotted, or Grid). '
          'Pan and zoom freely on an unbounded canvas.',
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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...PageLayout.values.map((l) {
                  final sel = l == layout.style;
                  return GestureDetector(
                    onTap: () => _onPageStyleTap(context, ref, layout, l),
                    child: _chip(l.chipLabel, sel),
                  );
                }),
                Container(
                  width: 1,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: ScrapTheme.dividers,
                ),
                Opacity(
                  opacity: lockedInfinite ? 0.55 : 1,
                  child: GestureDetector(
                    onTap: lockedInfinite
                        ? null
                        : () => _onInfiniteTap(context, ref, layout),
                    child: _chip('INFINITE', lockedInfinite),
                  ),
                ),
              ],
            ),
            if (lockedInfinite) ...[
              const SizedBox(height: 8),
              Text(
                'Infinite is locked for this note — you cannot return to a fixed page size.',
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
                  : 'Available only in Infinite mode.',
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
