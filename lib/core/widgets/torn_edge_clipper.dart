import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/scrapyard_theme.dart';

enum TornEdge { top, bottom, left, right }

/// Builds a seeded jagged path along [edge] of [size] (for ClipPath use).
Path buildTornEdgePath({
  required Size size,
  required int seed,
  TornEdge edge = TornEdge.bottom,
  double amplitude = 4.0,
}) {
  final rng = math.Random(seed);
  final path = Path();
  const step = 8.0;

  switch (edge) {
    case TornEdge.bottom:
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height - amplitude);
      for (double x = size.width; x >= 0; x -= step) {
        final y = size.height - amplitude + rng.nextDouble() * amplitude * 2;
        path.lineTo(x.clamp(0, size.width), y.clamp(0, size.height));
      }
      path.lineTo(0, size.height - amplitude);
      path.close();
      break;
    case TornEdge.top:
      path.moveTo(0, amplitude);
      for (double x = 0; x <= size.width; x += step) {
        final y = amplitude - rng.nextDouble() * amplitude * 2;
        path.lineTo(x.clamp(0, size.width), y.clamp(0, size.height));
      }
      path.lineTo(size.width, amplitude);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      break;
    case TornEdge.left:
      path.moveTo(amplitude, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(amplitude, size.height);
      for (double y = size.height; y >= 0; y -= step) {
        final x = amplitude - rng.nextDouble() * amplitude * 2;
        path.lineTo(x.clamp(0, size.width), y.clamp(0, size.height));
      }
      path.close();
      break;
    case TornEdge.right:
      path.moveTo(0, 0);
      path.lineTo(size.width - amplitude, 0);
      for (double y = 0; y <= size.height; y += step) {
        final x = size.width - amplitude + rng.nextDouble() * amplitude * 2;
        path.lineTo(x.clamp(0, size.width), y.clamp(0, size.height));
      }
      path.lineTo(size.width - amplitude, size.height);
      path.lineTo(0, size.height);
      path.close();
      break;
  }

  return path;
}

/// Clips a low-amplitude jagged deckle along one edge.
/// Prefer [TornEdgePainter] for cards — ClipPath allocates a GPU layer.
class TornEdgeClipper extends CustomClipper<Path> {
  final TornEdge edge;
  final int seed;
  final double amplitude;

  const TornEdgeClipper({
    this.edge = TornEdge.bottom,
    required this.seed,
    this.amplitude = 4.0,
  });

  @override
  Path getClip(Size size) => buildTornEdgePath(
        size: size,
        seed: seed,
        edge: edge,
        amplitude: amplitude,
      );

  @override
  bool shouldReclip(covariant TornEdgeClipper oldClipper) =>
      oldClipper.seed != seed ||
      oldClipper.edge != edge ||
      oldClipper.amplitude != amplitude;
}

/// Paints jagged notches in [fillColor] over the bottom of a card so the
/// page background shows through — one drawPath, no ClipPath / saveLayer.
class TornEdgePainter extends CustomPainter {
  final int seed;
  final double amplitude;
  final Color fillColor;

  const TornEdgePainter({
    required this.seed,
    this.amplitude = 4.0,
    this.fillColor = ScrapTheme.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    const step = 8.0;
    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Region from the jagged line down to the widget bottom = page show-through.
    final points = <Offset>[];
    for (double x = 0; x <= size.width; x += step) {
      final y = size.height - amplitude + rng.nextDouble() * amplitude * 2;
      points.add(Offset(x.clamp(0, size.width), y.clamp(0, size.height)));
    }
    if (points.isEmpty) return;

    final mask = Path()..moveTo(points.first.dx, points.first.dy);
    for (final o in points) {
      mask.lineTo(o.dx, o.dy);
    }
    mask
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(mask, paint);
  }

  @override
  bool shouldRepaint(covariant TornEdgePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.fillColor != fillColor;
}
