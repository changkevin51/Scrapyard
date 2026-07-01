import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/canvas_providers.dart';
import 'pen_settings_panel.dart';
import 'shape_library_panel.dart';
import 'sticker_library.dart';

// ─────────────────────────────────────────────────────────
// Tool definition — each tool has an icon, kanji label & tip
// ─────────────────────────────────────────────────────────
typedef _ToolDef = ({
  IconData icon,
  String kanji,
  String tip,
  CanvasTool tool,
});

const List<_ToolDef> _tools = [
  (icon: Icons.edit_outlined,      kanji: '筆', tip: 'Pen',          tool: CanvasTool.pen),
  (icon: Icons.brush_outlined,     kanji: '刷', tip: 'Brush',        tool: CanvasTool.brush),
  (icon: Icons.highlight_outlined, kanji: '光', tip: 'Highlighter',  tool: CanvasTool.highlighter),
  (icon: Icons.auto_fix_high,      kanji: '消', tip: 'Eraser',       tool: CanvasTool.eraser),
  (icon: Icons.horizontal_rule,    kanji: '線', tip: 'Straight line', tool: CanvasTool.straightLine),
  (icon: Icons.text_fields_outlined, kanji: '文', tip: 'Text',       tool: CanvasTool.text),
  (icon: Icons.category_outlined,  kanji: '形', tip: 'Shape',        tool: CanvasTool.shape),
  (icon: Icons.gesture,            kanji: '套', tip: 'Lasso',        tool: CanvasTool.lasso),
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
          icon: Icons.undo_outlined, kanji: '↩', tip: 'Undo',
          isIcon: isIcon, action: CanvasTool.undo),
      _ActionButton(
          icon: Icons.redo_outlined, kanji: '↪', tip: 'Redo',
          isIcon: isIcon, action: CanvasTool.redo),
      _sep(isHorizontal),

      // ── Colour palette ─────────────────────────────────
      for (final c in _palette) _ColorDot(color: c),
      _sep(isHorizontal),

      // ── Thickness dots ──────────────────────────────────
      _ThicknessDots(),
      _sep(isHorizontal),

      // ── Display-mode toggle (icon ↔ kanji) ─────────────
      _DisplayModeToggle(isIcon: isIcon),
      _sep(isHorizontal),

      // ── Settings sheet ─────────────────────────────────
      _SettingsButton(),
    ];

    return Container(
      width: isHorizontal ? double.infinity : null,
      height: isHorizontal ? null : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: KotoTheme.cardSurface,
        border: isHorizontal
            ? Border(
                bottom: position == ToolbarPosition.top
                    ? const BorderSide(color: KotoTheme.dividers)
                    : BorderSide.none,
                top: position == ToolbarPosition.bottom
                    ? const BorderSide(color: KotoTheme.dividers)
                    : BorderSide.none,
              )
            : Border(
                right: position == ToolbarPosition.left
                    ? const BorderSide(color: KotoTheme.dividers)
                    : BorderSide.none,
                left: position == ToolbarPosition.right
                    ? const BorderSide(color: KotoTheme.dividers)
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
      ? Container(width: 1, height: 20, color: KotoTheme.dividers,
          margin: const EdgeInsets.symmetric(horizontal: 6))
      : Container(height: 1, width: 20, color: KotoTheme.dividers,
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
        onTap: () => ref.read(isPenModeActiveProvider.notifier).state = !isPenMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isPenMode
                ? KotoTheme.accent.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: isIcon
              ? Icon(
                  isPenMode ? Icons.edit_outlined : Icons.pan_tool_alt_outlined,
                  size: 22,
                  color: isPenMode ? KotoTheme.accent : KotoTheme.mutedText,
                )
              : Text(
                  isPenMode ? '描' : '移',
                  style: KotoTextStyles.body.copyWith(
                    fontSize: 18,
                    color: isPenMode ? KotoTheme.accent : KotoTheme.mutedText,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tool button (icon or kanji based on mode)
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
                ? KotoTheme.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: isActive
                ? Border.all(
                    color: KotoTheme.accent.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              isIcon
                  ? Icon(def.icon, size: 22,
                      color: isActive ? KotoTheme.accent : KotoTheme.secondaryText)
                  : Text(def.kanji,
                      style: KotoTextStyles.body.copyWith(
                        fontSize: 18,
                        color: isActive ? KotoTheme.accent : KotoTheme.secondaryText,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      )),
              // Library shape indicator dot
              if (hasLibShape)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: KotoTheme.accent,
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
            color: isActive ? KotoTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? KotoTheme.accent.withValues(alpha: 0.35)
                  : KotoTheme.dividers,
              width: 1,
            ),
          ),
          child: Text(
            _labels[style]!,
            style: KotoTextStyles.label.copyWith(
              fontSize: 13,
              letterSpacing: 1.5,
              color: isActive ? KotoTheme.accent : KotoTheme.secondaryText,
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
  final String kanji;
  final String tip;
  final bool isIcon;
  final CanvasTool action;
  const _ActionButton(
      {required this.icon, required this.kanji, required this.tip,
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
          child: Icon(icon, size: 20, color: KotoTheme.secondaryText),
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
              message: 'Thickness ${val}×',
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: (mod - val).abs() < 0.3
                      ? KotoTheme.accent
                      : KotoTheme.dividers,
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
// Display-mode toggle  ↔  icon / kanji
// ─────────────────────────────────────────────────────────
class _DisplayModeToggle extends ConsumerWidget {
  final bool isIcon;
  const _DisplayModeToggle({required this.isIcon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: isIcon ? 'Switch to kanji mode' : 'Switch to icon mode',
      child: GestureDetector(
        onTap: () {
          final next = isIcon ? ToolbarDisplayMode.kanji : ToolbarDisplayMode.icons;
          ref.read(toolbarDisplayModeProvider.notifier).state = next;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            isIcon ? '文' : 'A',
            style: KotoTextStyles.body.copyWith(
              fontSize: 16,
              color: KotoTheme.mutedText,
              fontWeight: FontWeight.w500,
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
              ? const Icon(Icons.tune_outlined, size: 22, color: KotoTheme.mutedText)
              : Text('設',
                  style: KotoTextStyles.body
                      .copyWith(fontSize: 18, color: KotoTheme.mutedText)),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KotoTheme.cardSurface,
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
              style: KotoTextStyles.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 24),

          // Page layout
          Text('PAGE STYLE', style: KotoTextStyles.label),
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
          Text('TOOLBAR POSITION', style: KotoTextStyles.label),
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
                Text('PALM REJECTION', style: KotoTextStyles.label),
                Text('Stylus input only',
                    style: KotoTextStyles.caption
                        .copyWith(color: KotoTheme.mutedText)),
              ]),
              Switch(
                value: palmReject,
                onChanged: (v) =>
                    ref.read(stylusOnlyModeProvider.notifier).state = v,
                activeTrackColor: KotoTheme.accent,
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
          color: selected ? KotoTheme.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: selected ? KotoTheme.accent : KotoTheme.dividers),
        ),
        child: Text(
          label,
          style: KotoTextStyles.caption.copyWith(
            color: selected ? Colors.white : KotoTheme.secondaryText,
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
                  color: KotoTheme.mutedText)
              : Text('貼', style: KotoTextStyles.body.copyWith(
                  fontSize: 16, color: KotoTheme.mutedText)),
        ),
      ),
    );
  }
}
