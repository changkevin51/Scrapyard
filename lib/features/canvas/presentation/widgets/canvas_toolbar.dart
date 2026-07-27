import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../providers/canvas_providers.dart';
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
  (icon: Icons.highlight_outlined, label: 'Mark',  tip: 'Highlighter',  tool: CanvasTool.highlighter),
  (icon: Icons.auto_fix_high,      label: 'Erase', tip: 'Eraser',       tool: CanvasTool.eraser),
  (icon: Icons.horizontal_rule,    label: 'Line',  tip: 'Straight line', tool: CanvasTool.straightLine),
  (icon: Icons.text_fields_outlined, label: 'Text', tip: 'Text',       tool: CanvasTool.text),
  (icon: Icons.category_outlined,  label: 'Shape', tip: 'Shape',        tool: CanvasTool.shape),
  (icon: Icons.gesture,            label: 'Lasso', tip: 'Lasso',       tool: CanvasTool.lasso),
  (icon: Icons.auto_awesome,       label: 'Smelt', tip: 'Smelt',       tool: CanvasTool.smelt),
];

const List<Color> _palette = [
  Color(0xFF1C1C1C), // ink black
  Color(0xFF6B4C3B), // warm brown
  Color(0xFF4A4A4A), // pencil grey
  Color(0xFF8BAF7A), // sage green
  Color(0xFF7A9BB5), // slate blue
  Color(0xFFB58590), // dusty rose
];

// ─────────────────────────────────────────────────────────
// Main toolbar widget
// ─────────────────────────────────────────────────────────
class CanvasToolbar extends ConsumerWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPenMode    = ref.watch(isPenModeActiveProvider);
    final position     = ref.watch(toolbarPositionProvider);
    final displayMode  = ref.watch(toolbarDisplayModeProvider);
    final strokeStyle  = ref.watch(strokeStyleProvider);
    final isHorizontal = position == ToolbarPosition.top || position == ToolbarPosition.bottom;
    final isIcon       = displayMode == ToolbarDisplayMode.icons;

    final children = <Widget>[
      // ── Draw / Scroll mode toggle ──────────────────────
      _ModeToggle(isPenMode: isPenMode, isIcon: isIcon),
      _sep(isHorizontal),

      // ── All drawing tools – always exposed ─────────────
      for (final t in _tools)
        _ToolButton(def: t, isIcon: isIcon),
      PenSettingsButton(isIcon: isIcon),
      // Sticker library button
      _StickerButton(isIcon: isIcon),
      _sep(isHorizontal),

      // ── Stroke style chips – inline ────────────────────
      for (final s in StrokeStyle.values)
        _StrokeStyleChip(style: s, current: strokeStyle),
      _sep(isHorizontal),

      // ── Undo / Redo ────────────────────────────────────
      _ActionButton(
          icon: Icons.undo_outlined, tip: 'Undo',
          isIcon: isIcon, action: CanvasTool.undo),
      _ActionButton(
          icon: Icons.redo_outlined, tip: 'Redo',
          isIcon: isIcon, action: CanvasTool.redo),
      _sep(isHorizontal),

      // ── Colour palette ─────────────────────────────────
      for (final c in _palette) _ColorDot(color: c),
      _sep(isHorizontal),

      // ── Thickness dots ──────────────────────────────────
      const _ThicknessDots(),
      _sep(isHorizontal),

      // ── Display-mode toggle (icon ↔ label) ─────────────
      _DisplayModeToggle(isIcon: isIcon),
      _sep(isHorizontal),

      // ── Settings sheet ─────────────────────────────────
      const _SettingsButton(),
    ];

    return Container(
      width: isHorizontal ? double.infinity : null,
      height: isHorizontal ? null : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        border: isHorizontal
            ? Border(
                bottom: position == ToolbarPosition.top
                    ? const BorderSide(color: ScrapTheme.dividers)
                    : BorderSide.none,
                top: position == ToolbarPosition.bottom
                    ? const BorderSide(color: ScrapTheme.dividers)
                    : BorderSide.none,
              )
            : Border(
                right: position == ToolbarPosition.left
                    ? const BorderSide(color: ScrapTheme.dividers)
                    : BorderSide.none,
                left: position == ToolbarPosition.right
                    ? const BorderSide(color: ScrapTheme.dividers)
                    : BorderSide.none,
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
      ? Container(width: 1, height: 20, color: ScrapTheme.dividers,
          margin: const EdgeInsets.symmetric(horizontal: 6))
      : Container(height: 1, width: 20, color: ScrapTheme.dividers,
          margin: const EdgeInsets.symmetric(vertical: 6));
}

// ─────────────────────────────────────────────────────────
// Draw / Scroll mode toggle
// ─────────────────────────────────────────────────────────
class _ModeToggle extends ConsumerWidget {
  final bool isPenMode;
  final bool isIcon;
  const _ModeToggle({required this.isPenMode, required this.isIcon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isPenMode ? 'Switch to scroll/read mode' : 'Switch to draw mode',
      child: GestureDetector(
        onTap: () {
          final newMode = !isPenMode;
          ref.read(isPenModeActiveProvider.notifier).state = newMode;
          // When switching to touch/scroll mode, disable selection tools
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
          child: isIcon
              ? Icon(
                  isPenMode ? Icons.edit_outlined : Icons.pan_tool_alt_outlined,
                  size: 22,
                  color: isPenMode ? ScrapTheme.accent : ScrapTheme.mutedText,
                )
              : Text(
                  isPenMode ? 'Draw' : 'Move',
                  style: ScrapTextStyles.label.copyWith(
                    fontSize: 12,
                    color: isPenMode ? ScrapTheme.accent : ScrapTheme.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
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
  final bool isIcon;
  const _ToolButton({required this.def, required this.isIcon});

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
      child: GestureDetector(
        onTap: () {
          ref.read(activeCanvasToolProvider.notifier).state = def.tool;
          ref.read(isPenModeActiveProvider.notifier).state = true;
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
            border: isActive
                ? Border.all(
                    color: ScrapTheme.accent.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              isIcon
                  ? Icon(def.icon, size: 22,
                      color: isActive ? ScrapTheme.accent : ScrapTheme.secondaryText)
                  : Text(def.label,
                      style: ScrapTextStyles.label.copyWith(
                        fontSize: 11,
                        color: isActive ? ScrapTheme.accent : ScrapTheme.secondaryText,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      )),
              // Library shape indicator dot
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
      child: GestureDetector(
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
  final bool isIcon;
  final CanvasTool action;
  const _ActionButton(
      {required this.icon, required this.tip,
       required this.isIcon, required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: () {
          if (action == CanvasTool.undo) ref.read(strokesProvider.notifier).undo();
          if (action == CanvasTool.redo) ref.read(strokesProvider.notifier).redo();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // Always use icons for undo/redo — universally recognizable
          child: Icon(icon, size: 20, color: ScrapTheme.secondaryText),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Colour dots
// ─────────────────────────────────────────────────────────
class _ColorDot extends ConsumerWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(canvasColorProvider);
    final isSelected = current.toARGB32() == color.toARGB32();

    return GestureDetector(
      onTap: () => ref.read(canvasColorProvider.notifier).state = color,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        width: isSelected ? 22 : 18,
        height: isSelected ? 22 : 18,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 4, spreadRadius: 1)]
              : null,
        ),
      ),
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
          GestureDetector(
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
// Display-mode toggle  ↔  icon / label
// ─────────────────────────────────────────────────────────
class _DisplayModeToggle extends ConsumerWidget {
  final bool isIcon;
  const _DisplayModeToggle({required this.isIcon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isIcon ? 'Switch to label mode' : 'Switch to icon mode',
      child: GestureDetector(
        onTap: () {
          final next = isIcon ? ToolbarDisplayMode.labels : ToolbarDisplayMode.icons;
          ref.read(toolbarDisplayModeProvider.notifier).state = next;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            isIcon ? 'Aa' : '◆',
            style: ScrapTextStyles.label.copyWith(
              fontSize: 13,
              color: ScrapTheme.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
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
    final isIcon = ref.watch(toolbarDisplayModeProvider) == ToolbarDisplayMode.icons;
    return Tooltip(
      message: 'Canvas settings',
      child: GestureDetector(
        onTap: () => _showSettings(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: isIcon
              ? const Icon(Icons.tune_outlined, size: 22, color: ScrapTheme.mutedText)
              : Text('Set',
                  style: ScrapTextStyles.label.copyWith(
                    fontSize: 11,
                    color: ScrapTheme.mutedText,
                    fontWeight: FontWeight.w600,
                  )),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ScrapTheme.cardSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => const _CanvasSettingsSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Settings bottom sheet  (layout / dock / palm rejection)
// stroke style is now inline; kept here only for completeness
// ─────────────────────────────────────────────────────────
class _CanvasSettingsSheet extends ConsumerWidget {
  const _CanvasSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout       = ref.watch(pageLayoutProvider);
    final pos          = ref.watch(toolbarPositionProvider);
    final palmReject   = ref.watch(stylusOnlyModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Canvas Settings',
              style: ScrapTextStyles.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 24),

          // Page layout
          Text('PAGE STYLE', style: ScrapTextStyles.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: PageLayout.values.map((l) {
              final sel = l == layout;
              return GestureDetector(
                onTap: () => ref.read(pageLayoutProvider.notifier).state = l,
                child: _chip(l.name.toUpperCase(), sel),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Toolbar dock
          Text('TOOLBAR POSITION', style: ScrapTextStyles.label),
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
                Text('PALM REJECTION', style: ScrapTextStyles.label),
                Text('Touch = scroll/zoom, Stylus = write',
                    style: ScrapTextStyles.caption
                        .copyWith(color: ScrapTheme.mutedText)),
              ]),
              Switch(
                value: palmReject,
                onChanged: (v) =>
                    ref.read(stylusOnlyModeProvider.notifier).state = v,
                activeTrackColor: ScrapTheme.accent,
                thumbColor: const WidgetStatePropertyAll(Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
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
          style: ScrapTextStyles.caption.copyWith(
            color: selected ? Colors.white : ScrapTheme.secondaryText,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
// Sticker library toolbar button
// ─────────────────────────────────────────────────────────────────
class _StickerButton extends StatelessWidget {
  final bool isIcon;
  const _StickerButton({required this.isIcon});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sticker library',
      child: GestureDetector(
        onTap: () => showStickerLibrary(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: isIcon
              ? const Icon(Icons.emoji_emotions_outlined, size: 20,
                  color: ScrapTheme.mutedText)
              : Text('貼', style: ScrapTextStyles.body.copyWith(
                  fontSize: 16, color: ScrapTheme.mutedText)),
        ),
      ),
    );
  }
}
