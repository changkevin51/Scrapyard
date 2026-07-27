import 'package:flutter/material.dart';

import '../theme/scrap_feedback.dart';
import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';

/// Ember-glow thinking dots — paper alternative to CircularProgressIndicator.
class PaperDots extends StatefulWidget {
  final double size;
  final Color? color;

  const PaperDots({
    super.key,
    this.size = 6,
    this.color,
  });

  @override
  State<PaperDots> createState() => _PaperDotsState();
}

class _PaperDotsState extends State<PaperDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ember = Color(0xFF8A6A55);
    final base = widget.color ?? ScrapTheme.accent;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final progress = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = progress < 0.5 ? progress * 2 : 2 - progress * 2;
            final color = Color.lerp(base, ember, index / 2)!;
            return Container(
              width: widget.size,
              height: widget.size,
              margin: EdgeInsets.symmetric(horizontal: widget.size * 0.33),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Kraft track with a square ink-outlined paper tab.
class PaperSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const PaperSwitch({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled
            ? () {
                ScrapFeedback.tap();
                onChanged!(!value);
              }
            : null,
        child: AnimatedContainer(
          duration: ScrapMotion.press,
          curve: Curves.easeOut,
          width: 44,
          height: 24,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value
                ? ScrapTheme.accent.withValues(alpha: 0.18)
                : ScrapTheme.codeSurface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: value
                  ? ScrapTheme.accent.withValues(alpha: 0.5)
                  : ScrapTheme.dividers,
              width: 1,
            ),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: ScrapMotion.press,
            curve: Curves.easeOut,
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: ScrapTheme.cardSurface,
              borderRadius: BorderRadius.circular(1.5),
              border: Border.all(
                color: value ? ScrapTheme.accent : ScrapTheme.kraft,
                width: 1.25,
              ),
              boxShadow: value
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        offset: Offset(1, 1),
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
