import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';

class ExpandingRingFeedback extends StatefulWidget {
  final Offset position;
  final int stage; // 1: word, 2: sentence, 3: paragraph

  const ExpandingRingFeedback({super.key, required this.position, required this.stage});

  @override
  State<ExpandingRingFeedback> createState() => _ExpandingRingFeedbackState();
}

class _ExpandingRingFeedbackState extends State<ExpandingRingFeedback> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    // It should feel like ink seeping outward quietly.
    _opacityAnim = Tween<double>(begin: 0.1, end: 0.4).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }
  
  @override
  void didUpdateWidget(ExpandingRingFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) {
       _controller.reset();
       _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx,
      top: widget.position.dy,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final targetRadius = widget.stage == 1 ? 40.0 : widget.stage == 2 ? 80.0 : 160.0;
          final currentRadius = targetRadius * _scaleAnim.value;
          
          return Transform.translate(
            offset: Offset(-currentRadius, -currentRadius),
            child: Container(
              width: currentRadius * 2,
              height: currentRadius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: KotoTheme.accent.withValues(alpha: _opacityAnim.value), // Thin brown ring, slow opacity
                  width: 2.0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
