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
    // Heal in-memory settings from before eraserMode existed (hot reload).
    if (settings.eraserMode == null) {
      Future.microtask(() {
        ref.read(penSettingsProvider.notifier).state =
            settings.copyWith(eraserMode: EraserMode.stroke);
      });
    }
    final family = ref.watch(activeInkFamilyProvider);
    final isHighlighter = family == InkFamily.highlighter;
    final styles = PenStyleInfo.forFamily(family);
    final currentStyle = styles.isEmpty
        ? settings.penStyle
        : (styles.contains(settings.penStyle)
            ? settings.penStyle
            : styles.first);

    String stampFor(InkFamily f) => switch (f) {
          InkFamily.pen => '⟨ Pen ⟩',
          InkFamily.brush => '⟨ Brush ⟩',
          InkFamily.highlighter => '⟨ Highlighter ⟩',
        };
    String titleFor(InkFamily f) => switch (f) {
          InkFamily.pen => 'Pen Settings',
          InkFamily.brush => 'Brush Settings',
          InkFamily.highlighter => 'Highlighter Settings',
        };
    CanvasTool toolFor(InkFamily f) => switch (f) {
          InkFamily.pen => CanvasTool.pen,
          InkFamily.brush => CanvasTool.brush,
          InkFamily.highlighter => CanvasTool.highlighter,
        };

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
      decoration: const BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ScrapTheme.borderRadiusDefault),
        ),
      ),
      child: SingleChildScrollView(
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
          ScrapStampLabel(text: stampFor(family)),
          const SizedBox(height: 8),
          Text(
            titleFor(family),
            style: ScrapTextStyles.heading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),

          // ── Pen | Brush | Highlighter family tabs ──────────────
          _FamilyTabs(
            family: family,
            onChanged: (f) {
              ref.read(activeInkFamilyProvider.notifier).state = f;
              if (f != InkFamily.highlighter) {
                final nextStyles = PenStyleInfo.forFamily(f);
                final preferred = nextStyles.contains(settings.penStyle)
                    ? settings.penStyle
                    : nextStyles.first;
                ref.read(penSettingsProvider.notifier).state =
                    settings.copyWith(penStyle: preferred);
              }
              final tool = toolFor(f);
              ref.read(activeCanvasToolProvider.notifier).state = tool;
              restoreToolColor(ref, tool);
            },
          ),
          const SizedBox(height: 20),

          // ── Style selector (pen / brush only) ──────────────────
          if (!isHighlighter) ...[
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
                final tool = toolFor(s.family);
                ref.read(activeCanvasToolProvider.notifier).state = tool;
                restoreToolColor(ref, tool);
              },
            ),
            const SizedBox(height: 24),
          ],

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

          // ── Sensitivity (pen / brush styles that support it) ───
          if (!isHighlighter && currentStyle.hasSensitivity) ...[
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

          // ── Concentration (per tool) ───────────────────────────
          _SectionHeader(
            label: 'CONCENTRATION',
            value: '${(settings.concentrationFor(family) * 100).round()}%',
            tooltip: isHighlighter
                ? 'Highlighter density — how strong the highlight appears'
                : 'Ink density — controls stroke opacity',
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
                    value: settings.concentrationFor(family),
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    onChanged: (v) =>
                        ref.read(penSettingsProvider.notifier).state =
                            settings.withConcentration(family, v),
                  ),
                ),
              ),
              Text('Full',
                  style: ScrapTextStyles.caption
                      .copyWith(color: ScrapTheme.mutedText, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _ConcentrationPreview(
              concentration: settings.concentrationFor(family)),
          const SizedBox(height: 20),

          // ── Beautification toggle (pen / brush only) ───────────
          if (!isHighlighter) ...[
            _ToggleRow(
              label: 'SHAPE SNAPPING',
              subtitle: 'Hold still to snap strokes into clean shapes',
              value: settings.beautify,
              onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                  settings.copyWith(beautify: v),
            ),
            const SizedBox(height: 24),
          ],

          // ── Eraser ─────────────────────────────────────────────
          _SectionHeader(
            label: 'ERASER',
            value: settings.eraser.label,
            tooltip: settings.eraser.description,
          ),
          const SizedBox(height: 8),
          _EraserModeTabs(
            mode: settings.eraser,
            onChanged: (m) => ref.read(penSettingsProvider.notifier).state =
                settings.copyWith(eraserMode: m),
          ),
          const SizedBox(height: 8),
          Text(
            settings.eraser == EraserMode.area
                ? 'Area size follows the thickness dots in the toolbar.'
                : 'Removes whole strokes the eraser brush touches.',
            style: ScrapTextStyles.caption
                .copyWith(color: ScrapTheme.mutedText, fontSize: 11),
          ),
        ],
      ),
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
    return _SegmentedTabs<InkFamily>(
      value: family,
      options: const [
        (label: 'Pen', value: InkFamily.pen),
        (label: 'Brush', value: InkFamily.brush),
        (label: 'Highlighter', value: InkFamily.highlighter),
      ],
      onChanged: onChanged,
    );
  }
}

class _EraserModeTabs extends StatelessWidget {
  final EraserMode mode;
  final ValueChanged<EraserMode> onChanged;

  const _EraserModeTabs({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _SegmentedTabs<EraserMode>(
      value: mode,
      options: const [
        (label: 'Stroke', value: EraserMode.stroke),
        (label: 'Area', value: EraserMode.area),
      ],
      onChanged: onChanged,
    );
  }
}

class _SegmentedTabs<T> extends StatelessWidget {
  final T value;
  final List<({String label, T value})> options;
  final ValueChanged<T> onChanged;

  const _SegmentedTabs({
    required this.value,
    required this.options,
    required this.onChanged,
  });

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
          for (final opt in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(opt.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: value == opt.value
                        ? ScrapTheme.accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    opt.label,
                    style: ScrapTextStyles.label.copyWith(
                      color: value == opt.value
                          ? Colors.white
                          : ScrapTheme.secondaryText,
                      fontWeight: value == opt.value
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
    final isRelevant = activeTool == CanvasTool.pen ||
        activeTool == CanvasTool.brush ||
        activeTool == CanvasTool.highlighter ||
        activeTool == CanvasTool.eraser;

    return Tooltip(
      message: 'Pen / Brush / Highlighter / Eraser settings',
      child: GestureDetector(
        onTap: () {
          // Sync family tab to the active drawing tool when opening.
          final family = switch (activeTool) {
            CanvasTool.brush => InkFamily.brush,
            CanvasTool.highlighter => InkFamily.highlighter,
            _ => InkFamily.pen,
          };
          if (activeTool == CanvasTool.pen ||
              activeTool == CanvasTool.brush ||
              activeTool == CanvasTool.highlighter) {
            ref.read(activeInkFamilyProvider.notifier).state = family;
          }
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
            color: isRelevant
                ? ScrapTheme.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            Icons.tune,
            size: 18,
            color: isRelevant ? ScrapTheme.accent : ScrapTheme.mutedText,
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
