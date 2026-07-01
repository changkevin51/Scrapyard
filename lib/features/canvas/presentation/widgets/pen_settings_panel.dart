import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../data/pen_engine.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Pen Settings Panel
// Shown as a modal bottom sheet.
// ─────────────────────────────────────────────────────────────────
class PenSettingsPanel extends ConsumerWidget {
  const PenSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(penSettingsProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
      decoration: const BoxDecoration(
        color: KotoTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: KotoTheme.dividers,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Pen Settings', style: KotoTextStyles.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 24),

          // ── Pen Style ──────────────────────────────────────────────
          _SectionHeader(
            label: 'PEN STYLE',
            value: settings.penStyle.label,
            tooltip: 'The physical rendering algorithm for the pen',
          ),
          const SizedBox(height: 12),
          _PenStyleSelector(
            currentStyle: settings.penStyle,
            onChanged: (s) => ref.read(penSettingsProvider.notifier).state =
                settings.copyWith(penStyle: s),
          ),
          const SizedBox(height: 24),

          // ── Stability ──────────────────────────────────────────────
          _SectionHeader(
            label: 'STABILITY',
            value: '${(settings.stability * 100).round()}%',
            tooltip: 'Lazy-rope smoothing — reduces hand tremor',
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Raw', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: settings.stability,
                    min: 0.0, max: 1.0, divisions: 20,
                    onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                        settings.copyWith(stability: v),
                  ),
                ),
              ),
              Text('Max', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _StabilityPreview(stability: settings.stability),
          const SizedBox(height: 20),

          // ── Concentration ─────────────────────────────────────────
          _SectionHeader(
            label: 'CONCENTRATION',
            value: '${(settings.concentration * 100).round()}%',
            tooltip: 'Ink density — controls stroke opacity',
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Light', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: settings.concentration,
                    min: 0.1, max: 1.0, divisions: 18,
                    onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                        settings.copyWith(concentration: v),
                  ),
                ),
              ),
              Text('Full', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          _ConcentrationPreview(concentration: settings.concentration),
          const SizedBox(height: 20),

          // ── Toggles ───────────────────────────────────────────────
          _ToggleRow(
            label: 'HANDWRITING BEAUTIFICATION',
            subtitle: 'Smooth strokes with real-time Bézier curves',
            value: settings.beautify,
            onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                settings.copyWith(beautify: v),
          ),
          const Divider(color: KotoTheme.dividers, height: 24),
          _ToggleRow(
            label: 'STROKE PREDICTION',
            subtitle: 'Show a ghost continuation ahead of your stroke',
            value: settings.predict,
            onChanged: (v) => ref.read(penSettingsProvider.notifier).state =
                settings.copyWith(predict: v),
          ),
        ],
      ),
    );
  }

  SliderThemeData _sliderTheme(BuildContext context) => SliderTheme.of(context).copyWith(
    activeTrackColor: KotoTheme.accent,
    thumbColor: KotoTheme.accent,
    inactiveTrackColor: KotoTheme.dividers,
    overlayColor: KotoTheme.accent.withValues(alpha: 0.12),
    trackHeight: 2,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
  );
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
          child: Text(label, style: KotoTextStyles.label),
        ),
        const Spacer(),
        Text(value,
            style: KotoTextStyles.caption.copyWith(
                color: KotoTheme.accent, fontWeight: FontWeight.w600)),
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
              Text(label, style: KotoTextStyles.label),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: KotoTextStyles.caption
                      .copyWith(color: KotoTheme.mutedText)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: KotoTheme.accent,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Stability live preview — shows a wavy line that straightens
// as stability increases
// ─────────────────────────────────────────────────────────────────
class _StabilityPreview extends StatelessWidget {
  final double stability;
  const _StabilityPreview({required this.stability});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(painter: _StabilityPainter(stability)),
    );
  }
}

class _StabilityPainter extends CustomPainter {
  final double stability;
  const _StabilityPainter(this.stability);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = KotoTheme.accent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final amplitude = (1 - stability) * 6; // jitter decreases with stability
    final w = size.width, h = size.height / 2;
    path.moveTo(0, h);

    for (double x = 0; x < w; x += 4) {
      final jitter = amplitude * (0.5 - (x / w)) * 2;
      path.lineTo(x, h + jitter);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StabilityPainter old) =>
      old.stability != stability;
}

// ─────────────────────────────────────────────────────────────────
// Concentration preview — fading stroke
// ─────────────────────────────────────────────────────────────────
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
            KotoTheme.accent.withValues(alpha: 0.05),
            KotoTheme.accent.withValues(alpha: concentration),
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
  final bool isIcon;
  const PenSettingsButton({super.key, required this.isIcon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTool = ref.watch(activeCanvasToolProvider);
    final isPen = activeTool == CanvasTool.pen;

    return Tooltip(
      message: 'Pen settings',
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
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
            color: isPen
                ? KotoTheme.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: isIcon
              ? Icon(Icons.tune, size: 18,
                  color: isPen ? KotoTheme.accent : KotoTheme.mutedText)
              : Text('調',
                  style: KotoTextStyles.body.copyWith(
                      fontSize: 16,
                      color: isPen ? KotoTheme.accent : KotoTheme.mutedText)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Pen Style Horizontal Selector
// ─────────────────────────────────────────────────────────────────
class _PenStyleSelector extends StatelessWidget {
  final PenStyle currentStyle;
  final ValueChanged<PenStyle> onChanged;

  const _PenStyleSelector({
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
        itemCount: PenStyle.values.length,
        itemBuilder: (ctx, i) {
          final style = PenStyle.values[i];
          final isSelected = style == currentStyle;

          return GestureDetector(
            onTap: () => onChanged(style),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 86,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected ? KotoTheme.accent : KotoTheme.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? KotoTheme.accent : KotoTheme.dividers,
                  width: 1.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: KotoTheme.accent.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    style.kanji,
                    style: TextStyle(
                      fontFamily: 'Noto Serif',
                      fontSize: 24,
                      color: isSelected ? Colors.white : KotoTheme.primaryText,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    style.label,
                    style: KotoTextStyles.caption.copyWith(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : KotoTheme.secondaryText,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Tiny stroke preview
                  SizedBox(
                    height: 12, width: 60,
                    child: CustomPaint(
                      painter: _MiniStrokePainter(
                        style: style,
                        color: isSelected ? Colors.white : KotoTheme.primaryText,
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
    StrokeRenderer.paintPreview(canvas, size, color, style, 1.8);
  }
  @override
  bool shouldRepaint(covariant _MiniStrokePainter old) =>
      old.style != style || old.color != color;
}
