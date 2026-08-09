import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../providers/canvas_providers.dart';

/// Colour dots — ink-well ring, no blur glow.
/// Palm rejection on: pen tap selects colour; finger tap opens picker.
/// Palm rejection off: single tap selects; double tap opens picker.
class InkColorDot extends ConsumerStatefulWidget {
  final Color color;
  final int index;
  const InkColorDot({super.key, required this.color, required this.index});

  @override
  ConsumerState<InkColorDot> createState() => _InkColorDotState();
}

class _InkColorDotState extends ConsumerState<InkColorDot> {
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

/// Ink colour picker — scrap dialog wrapping flutter_colorpicker.
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

class _InkColorPickerDialogState extends ConsumerState<_InkColorPickerDialog> {
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
                            width: _picked.toARGB32() == c.toARGB32() ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
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
