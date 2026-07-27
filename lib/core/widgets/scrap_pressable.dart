import 'package:flutter/material.dart';

import '../theme/scrap_motion.dart';

/// Shared press-scale feedback for scrap-paper surfaces.
class ScrapPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final Curve curve;

  const ScrapPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.duration = ScrapMotion.press,
    this.curve = Curves.easeOut,
  });

  @override
  State<ScrapPressable> createState() => _ScrapPressableState();
}

class _ScrapPressableState extends State<ScrapPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null
            ? null
            : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null
            ? null
            : () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1.0,
          duration: widget.duration,
          curve: widget.curve,
          child: widget.child,
        ),
      ),
    );
  }
}
