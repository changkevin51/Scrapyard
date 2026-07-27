import 'package:flutter/material.dart';

import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';

/// Ink-stamp type label — mono, wide tracking, faint outline, slight tilt.
class ScrapStampLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final double tiltDegrees;

  const ScrapStampLabel({
    super.key,
    required this.text,
    this.color,
    this.tiltDegrees = -2.0,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? ScrapTheme.accent;
    return Transform.rotate(
      angle: tiltDegrees * 3.1415926535 / 180,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: ScrapTheme.tape.withValues(alpha: 0.9),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(2),
          color: c.withValues(alpha: 0.04),
        ),
        child: Text(
          text,
          style: ScrapTextStyles.stamp.copyWith(color: c),
        ),
      ),
    );
  }
}

/// One-shot staggered slide entrance — transform only, no FadeTransition.
/// Opacity compositing allocates saveLayer textures and OOM'd Impeller.
class ScrapCardEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration stagger;

  const ScrapCardEntrance({
    super.key,
    required this.child,
    required this.index,
    this.stagger = const Duration(milliseconds: 40),
  });

  @override
  State<ScrapCardEntrance> createState() => _ScrapCardEntranceState();
}

class _ScrapCardEntranceState extends State<ScrapCardEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<Offset> _offset;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(
      vsync: this,
      duration: ScrapMotion.cardEnter,
    );
    _controller = controller;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: controller,
      curve: ScrapMotion.cardEnterCurve,
    ));

    final delayMs =
        (widget.index * widget.stagger.inMilliseconds).clamp(0, 320);
    Future.delayed(Duration(milliseconds: delayMs), () async {
      if (!mounted || _controller == null) return;
      await _controller!.forward();
      if (!mounted) return;
      _controller!.dispose();
      _controller = null;
      setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return SlideTransition(
      position: _offset,
      child: widget.child,
    );
  }
}
