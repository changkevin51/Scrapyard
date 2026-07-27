import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tilts a child by a small, seed-derived angle so a grid of cards
/// reads as a scattered pile. Straightens slightly on press (no
/// continuous AnimatedContainer / matrix animation — that was thrashing
/// Impeller on tablet).
class ScrapTilt extends StatelessWidget {
  final Widget child;
  final int seed;
  final double maxDegrees;
  final bool enabled;

  const ScrapTilt({
    super.key,
    required this.child,
    required this.seed,
    this.maxDegrees = 1.2,
    this.enabled = true,
  });

  double get _restRadians {
    if (!enabled) return 0;
    final t = ((seed % 2001) / 1000.0) - 1.0; // -1..1
    return t * maxDegrees * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _restRadians,
      alignment: Alignment.center,
      child: child,
    );
  }
}
