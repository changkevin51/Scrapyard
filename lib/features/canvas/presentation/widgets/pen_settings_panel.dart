import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../data/ink_renderer.dart';
import '../../data/pen_engine.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Pen Settings Panel
// Shown as a modal bottom sheet. Adapts to Pen Mode vs Brush Mode.
// ─────────────────────────────────────────────────────────────────
class PenSettingsPanel extends ConsumerWidget {
  const PenSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(penSettingsProvider);
    final family = ref.watch(activeInkFamilyProvider);
    final styles = PenStyleInfo.forFamily(family);
    final currentStyle = styles.contains(settings.penStyle)
        ? settings.penStyle
        : styles.first;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
      decoration: const BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ScrapTheme.borderRadiusDefault),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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
          ScrapStampLabel(
            text: family == InkFamily.pen ? '⟨ Pen ⟩' : '⟨ Brush ⟩',
          ),
          const SizedBox(height: 8),
          Text(
            family == InkFamily.pen ? 'Pen Settings' : 'Brush Settings',
            style: ScrapTextStyles.heading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),

          // ── Pen | Brush family tabs ────────────────────────────
          _FamilyTabs(
            family: family,
            onChanged: (f) {
              ref.read(activeInkFamilyProvider.notifier).state = f;
              final nextStyles = PenStyleInfo.forFamily(f);
              final preferred = nextStyles.contains(settings.penStyle)
                  ? settings.penStyle
                  : nextStyles.first;
              ref.read(penSettingsProvider.notifier).state =
                  settings.copyWith(penStyle: preferred);
              ref.read(activeCanvasToolProvider.notifier).state =
                  f == InkFamily.pen ? CanvasTool.pen : CanvasTool.brush;
            },
          ),
          const SizedBox(height: 20),

          // ── Style selector (filtered by family) ────────────────
          _SectionHeader(
            label: family == InkFamily.pen ? 'PEN STYLE' : 'BRUSH STYLE',
            value: currentStyle.label,
            tooltip: 'The physical rendering algorithm',
          ),
          const SizedBox(height: 12),
          _PenStyleSelector(
            styles: styles,
            currentStyle: currentStyle,
            onChanged: (s) {
              ref.read(penSettingsProvider.notifier).state =
                  settings.copyWith(penStyle: s);
              ref.read(activeInkFamilyProvider.notifier).state = s.family;
              ref.read(activeCanvasToolProvider.notifier).state =
                  s.family == InkFamily.pen
                      ? CanvasTool.pen
                      : CanvasTool.brush;
            },
          ),
          const SizedBox(height: 24),

          // ── Streamline (was Stability) ─────────────────────────
          _SectionHeader(
            label: 'STREAMLINE',
            value: '${(settings.streamline * 100).round()}%',
            tooltip: 'Smooths input without introducing lag',
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Raw',
                  style: ScrapTextStyles.caption
                      .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: settings.streamline.clamp(0.0, 0.65),
                    min: 0.0,
                    max: 0.65,
                    divisions: 13,
                    onChanged: (v) =>
                        ref.read(penSettingsProvider.notifier).state =
                            settings.copyWith(streamline: v),
                  ),
                ),
              ),
              Text('Smooth',
                  style: ScrapTextStyles.caption
                      .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _StreamlinePreview(streamline: settings.streamline),
          const SizedBox(height: 20),

          // ── Sensitivity (conditional) ──────────────────────────
          if (currentStyle.hasSensitivity) ...[
            _SectionHeader(
              label: 'SENSITIVITY',
              value:
                  '${(settings.sensitivityFor(currentStyle) * 100).round()}%',
              tooltip: 'How strongly pressure affects stroke width',
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Soft',
                    style: ScrapTextStyles.caption
                        .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
                Expanded(
                  child: SliderTheme(
                    data: _sliderTheme(context),
                    child: Slider(
                      value: settings.sensitivityFor(currentStyle),
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (v) =>
                          ref.read(penSettingsProvider.notifier).state =
                              settings.withSensitivity(currentStyle, v),
                    ),
                  ),
                ),
                Text('Firm',
                    style: ScrapTextStyles.caption
                        .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // ── Concentration ──────────────────────────────────────
          _SectionHeader(
            label: 'CONCENTRATION',
            value: '${(settings.concentration * 100).round()}%',
            tooltip: 'Ink density — controls stroke opacity',
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Light',
                  style: ScrapTextStyles.caption
                      .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: settings.concentration,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    onChanged: (v) =>
                        ref.read(penSettingsProvider.notifier).state =
                            settings.copyWith(concentration: v),
                  ),
                ),
              ),
              Text('Full',
                  style: ScrapTextStyles.caption
                      .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _ConcentrationPreview(concentration: settings.concentration),
          const SizedBox(height: 20),

          // ── Beautification toggle ──────────────────────────────
          _ToggleRow(
            label: 'SHAPE SNAPPING',
            subtitle: 'Hold still to snap strokes into clean shapes',
            value: settings.beautify,
            onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                settings.copyWith(beautify: v),
          ),
        ],
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) =>
      SliderTheme.of(context).copyWith(
        activeTrackColor: ScrapTheme.accent,
        thumbColor: ScrapTheme.accent,
        inactiveTrackColor: ScrapTheme.dividers,
        overlayColor: ScrapTheme.accent.withValues(alpha: 0.12),
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      );
}

// ─────────────────────────────────────────────────────────────────
// Pen | Brush segmented tabs
// ─────────────────────────────────────────────────────────────────
class _FamilyTabs extends StatelessWidget {
  final InkFamily family;
  final ValueChanged<InkFamily> onChanged;

  const _FamilyTabs({required this.family, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ScrapTheme.kraft.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tab('Pen', InkFamily.pen),
          _tab('Brush', InkFamily.brush),
        ],
      ),
    );
  }

  Widget _tab(String label, InkFamily value) {
    final selected = family == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? ScrapTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: ScrapTextStyles.label.copyWith(
              color: selected ? Colors.white : ScrapTheme.secondaryText,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String value;
  final String tooltip;

  const _SectionHeader({
    required this.label,
    required this.value,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: tooltip,
          child: Text(label, style: ScrapTextStyles.stamp.copyWith(fontSize: 10)),
        ),
        const Spacer(),
        Text(
          value,
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ScrapTextStyles.label),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: ScrapTextStyles.caption
                    .copyWith(color: ScrapTheme.mutedText),
              ),
            ],
          ),
        ),
        PaperSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _StreamlinePreview extends StatelessWidget {
  final double streamline;
  const _StreamlinePreview({required this.streamline});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(painter: _StreamlinePainter(streamline)),
    );
  }
}

class _StreamlinePainter extends CustomPainter {
  final double streamline;
  const _StreamlinePainter(this.streamline);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ScrapTheme.accent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final amplitude = (1 - streamline / 0.65) * 6;
    final w = size.width;
    final h = size.height / 2;
    path.moveTo(0, h);
    for (double x = 0; x < w; x += 4) {
      final jitter = amplitude * (0.5 - (x / w)) * 2;
      path.lineTo(x, h + jitter);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StreamlinePainter old) =>
      old.streamline != streamline;
}

class _ConcentrationPreview extends StatelessWidget {
  final double concentration;
  const _ConcentrationPreview({required this.concentration});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          colors: [
            ScrapTheme.accent.withValues(alpha: 0.05),
            ScrapTheme.accent.withValues(alpha: concentration),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Compact inline pen-settings button for the toolbar
// ─────────────────────────────────────────────────────────────────
class PenSettingsButton extends ConsumerWidget {
  const PenSettingsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTool = ref.watch(activeCanvasToolProvider);
    final isInkTool =
        activeTool == CanvasTool.pen || activeTool == CanvasTool.brush;

    return Tooltip(
      message: 'Pen / Brush settings',
      child: GestureDetector(
        onTap: () {
          showScrapSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const PenSettingsPanel(),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isInkTool
                ? ScrapTheme.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.tune,
            size: 18,
            color: isInkTool ? ScrapTheme.accent : ScrapTheme.mutedText,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Style Horizontal Selector (family-filtered)
// ─────────────────────────────────────────────────────────────────
class _PenStyleSelector extends StatelessWidget {
  final List<PenStyle> styles;
  final PenStyle currentStyle;
  final ValueChanged<PenStyle> onChanged;

  const _PenStyleSelector({
    required this.styles,
    required this.currentStyle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: styles.length,
        itemBuilder: (ctx, i) {
          final style = styles[i];
          final isSelected = style == currentStyle;

          return GestureDetector(
            onTap: () => onChanged(style),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 86,
              margin: const EdgeInsets.only(right: 12),
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color:
                    isSelected ? ScrapTheme.accent : ScrapTheme.cardSurface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      isSelected ? ScrapTheme.accent : ScrapTheme.dividers,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    style.label.substring(0, 1),
                    style: ScrapTextStyles.heading.copyWith(
                      fontSize: 22,
                      color: isSelected
                          ? Colors.white
                          : ScrapTheme.primaryText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    style.label,
                    style: ScrapTextStyles.caption.copyWith(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : ScrapTheme.secondaryText,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 12,
                    width: 60,
                    child: CustomPaint(
                      painter: _MiniStrokePainter(
                        style: style,
                        color: isSelected
                            ? Colors.white
                            : ScrapTheme.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MiniStrokePainter extends CustomPainter {
  final PenStyle style;
  final Color color;
  const _MiniStrokePainter({required this.style, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    InkRenderer.paintPreview(canvas, size, color, style);
  }

  @override
  bool shouldRepaint(covariant _MiniStrokePainter old) =>
      old.style != style || old.color != color;
}
