import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/scrapyard_theme.dart';

enum TornEdge { top, bottom, left, right }

/// Organic deckle samples along an edge of [length].
///
/// Combines slow undulation, mid-frequency waves, and irregular micro-bites
/// so the tear reads as paper fibre rather than a repeating zigzag.
List<({double along, double perp})> _deckleSamples({
  required double length,
  required int seed,
  required double amplitude,
}) {
  final rng = math.Random(seed);
  final slowAmp = amplitude * 0.55;
  final midAmp = amplitude * 0.38;
  final microAmp = amplitude * 0.28;
  final slowFreq = 0.012 + rng.nextDouble() * 0.01;
  final midFreq = 0.055 + rng.nextDouble() * 0.035;
  final slowPhase = rng.nextDouble() * math.pi * 2;
  final midPhase = rng.nextDouble() * math.pi * 2;

  double sampleAt(double s) {
    final slow = math.sin(s * slowFreq + slowPhase) * slowAmp;
    final mid = math.sin(s * midFreq + midPhase) * midAmp;
    final micro = (rng.nextDouble() - 0.45) * 2 * microAmp;
    // Occasional deeper bite — torn paper isn't uniform.
    final bite = rng.nextDouble() < 0.07
        ? amplitude *
            (0.35 + rng.nextDouble() * 0.55) *
            (rng.nextBool() ? 1 : -1)
        : 0.0;
    final endFade = _endFade(s, length, amplitude * 3);
    return ((slow + mid + micro + bite) * endFade)
        .clamp(-amplitude * 1.15, amplitude * 1.15);
  }

  final samples = <({double along, double perp})>[];
  double s = 0;
  while (s < length - 0.5) {
    samples.add((along: s, perp: sampleAt(s)));
    s += 2.5 + rng.nextDouble() * 6.5; // irregular spacing
  }
  // Exact end sample, quieter.
  final endPerp = (math.sin(length * slowFreq + slowPhase) * slowAmp +
          math.sin(length * midFreq + midPhase) * midAmp) *
      _endFade(length, length, amplitude * 3);
  samples.add((
    along: length,
    perp: endPerp.clamp(-amplitude * 0.4, amplitude * 0.4),
  ));
  return samples;
}

double _endFade(double s, double length, double fadeDist) {
  if (length <= 0) return 1;
  final d = math.min(s, length - s);
  if (d >= fadeDist) return 1;
  final t = (d / fadeDist).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t); // smoothstep
}

/// Map deckle samples to canvas offsets via [toPoint](along, perp).
List<Offset> _decklePoints({
  required List<({double along, double perp})> samples,
  required Offset Function(double along, double perp) toPoint,
}) {
  if (samples.isEmpty) return const [];
  return [
    for (final s in samples) toPoint(s.along, s.perp),
  ];
}

/// Smooth open polyline through [points] using mid-point quadratic beziers.
Path _smoothOpenPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return path;
  }
  // Line to first midpoint, then quadratic through each vertex.
  final firstMid = Offset(
    (points[0].dx + points[1].dx) / 2,
    (points[0].dy + points[1].dy) / 2,
  );
  path.lineTo(firstMid.dx, firstMid.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset(
      (points[i].dx + points[i + 1].dx) / 2,
      (points[i].dy + points[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// Builds a seeded organic deckle path along [edge] of [size] (for ClipPath).
///
/// Positive perp bites into the sheet (reveals whatever sits behind).
Path buildTornEdgePath({
  required Size size,
  required int seed,
  TornEdge edge = TornEdge.bottom,
  double amplitude = 4.0,
}) {
  final length = switch (edge) {
    TornEdge.top || TornEdge.bottom => size.width,
    TornEdge.left || TornEdge.right => size.height,
  };
  final samples =
      _deckleSamples(length: length, seed: seed, amplitude: amplitude);
  // Center the wiggle on [amplitude] so protrusions stay inside the bounds
  // while bites cut into the sheet.
  final base = amplitude;

  final path = Path();
  switch (edge) {
    case TornEdge.bottom:
      {
        final pts = _decklePoints(
          samples: samples,
          toPoint: (along, perp) => Offset(
            along.clamp(0, size.width),
            (size.height - base + perp).clamp(0, size.height),
          ),
        );
        path.moveTo(0, 0);
        path.lineTo(size.width, 0);
        path.lineTo(pts.last.dx, pts.last.dy);
        _appendSmooth(path, pts.reversed.toList());
        path.lineTo(0, 0);
        path.close();
      }
      break;
    case TornEdge.top:
      {
        final pts = _decklePoints(
          samples: samples,
          toPoint: (along, perp) => Offset(
            along.clamp(0, size.width),
            (base - perp).clamp(0, size.height),
          ),
        );
        path.moveTo(pts.first.dx, pts.first.dy);
        _appendSmooth(path, pts);
        path.lineTo(size.width, size.height);
        path.lineTo(0, size.height);
        path.close();
      }
      break;
    case TornEdge.left:
      {
        final pts = _decklePoints(
          samples: samples,
          // +perp bites into the sheet (rightward).
          toPoint: (along, perp) => Offset(
            (base + perp).clamp(0, size.width),
            along.clamp(0, size.height),
          ),
        );
        path.moveTo(pts.first.dx, pts.first.dy);
        _appendSmooth(path, pts);
        path.lineTo(size.width, size.height);
        path.lineTo(size.width, 0);
        path.close();
      }
      break;
    case TornEdge.right:
      {
        final pts = _decklePoints(
          samples: samples,
          toPoint: (along, perp) => Offset(
            (size.width - base - perp).clamp(0, size.width),
            along.clamp(0, size.height),
          ),
        );
        path.moveTo(0, 0);
        path.lineTo(pts.first.dx, pts.first.dy);
        _appendSmooth(path, pts);
        path.lineTo(0, size.height);
        path.close();
      }
      break;
  }
  return path;
}

void _appendSmooth(Path path, List<Offset> points) {
  if (points.isEmpty) return;
  if (points.length == 1) {
    path.lineTo(points.first.dx, points.first.dy);
    return;
  }
  if (points.length == 2) {
    path.lineTo(points[1].dx, points[1].dy);
    return;
  }
  final firstMid = Offset(
    (points[0].dx + points[1].dx) / 2,
    (points[0].dy + points[1].dy) / 2,
  );
  path.lineTo(firstMid.dx, firstMid.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset(
      (points[i].dx + points[i + 1].dx) / 2,
      (points[i].dy + points[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
}

/// Open smooth tear polyline along [edge] (for overlay painters).
Path buildTornEdgePolyline({
  required Size size,
  required int seed,
  TornEdge edge = TornEdge.bottom,
  double amplitude = 4.0,
}) {
  final length = switch (edge) {
    TornEdge.top || TornEdge.bottom => size.width,
    TornEdge.left || TornEdge.right => size.height,
  };
  final samples =
      _deckleSamples(length: length, seed: seed, amplitude: amplitude);
  final base = amplitude;

  final pts = switch (edge) {
    TornEdge.bottom => _decklePoints(
        samples: samples,
        toPoint: (along, perp) => Offset(
          along.clamp(0, size.width),
          (size.height - base + perp).clamp(0, size.height),
        ),
      ),
    TornEdge.top => _decklePoints(
        samples: samples,
        toPoint: (along, perp) => Offset(
          along.clamp(0, size.width),
          (base - perp).clamp(0, size.height),
        ),
      ),
    TornEdge.left => _decklePoints(
        samples: samples,
        toPoint: (along, perp) => Offset(
          (base + perp).clamp(0, size.width),
          along.clamp(0, size.height),
        ),
      ),
    TornEdge.right => _decklePoints(
        samples: samples,
        toPoint: (along, perp) => Offset(
          (size.width - base - perp).clamp(0, size.width),
          along.clamp(0, size.height),
        ),
      ),
  };
  return _smoothOpenPath(pts);
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

/// Paints jagged notches in [fillColor] over one edge of a card so the
/// page background shows through — one drawPath, no ClipPath / saveLayer.
class TornEdgePainter extends CustomPainter {
  final int seed;
  final double amplitude;
  final Color fillColor;
  final TornEdge edge;

  const TornEdgePainter({
    required this.seed,
    this.amplitude = 4.0,
    this.fillColor = ScrapTheme.background,
    this.edge = TornEdge.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final tear = buildTornEdgePolyline(
      size: size,
      seed: seed,
      edge: edge,
      amplitude: amplitude,
    );

    final mask = Path.from(tear);
    switch (edge) {
      case TornEdge.bottom:
        mask
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        break;
      case TornEdge.top:
        mask
          ..lineTo(size.width, 0)
          ..lineTo(0, 0)
          ..close();
        break;
      case TornEdge.left:
        // Tear runs top→bottom; fill everything to the left of it.
        mask
          ..lineTo(0, size.height)
          ..lineTo(0, 0)
          ..close();
        break;
      case TornEdge.right:
        mask
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0)
          ..close();
        break;
    }
    canvas.drawPath(mask, paint);
  }

  @override
  bool shouldRepaint(covariant TornEdgePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.edge != edge;
}

/// Soft contact shadow that follows a torn [edge].
class TornEdgeShadowPainter extends CustomPainter {
  final int seed;
  final double amplitude;
  final TornEdge edge;
  final Color color;

  const TornEdgeShadowPainter({
    required this.seed,
    this.amplitude = 5.0,
    this.edge = TornEdge.left,
    this.color = const Color(0x14000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tear = buildTornEdgePolyline(
      size: size,
      seed: seed,
      edge: edge,
      amplitude: amplitude,
    );
    final shadow = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.5)
      ..isAntiAlias = true;
    canvas.drawPath(tear, shadow);
  }

  @override
  bool shouldRepaint(covariant TornEdgeShadowPainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.edge != edge ||
      oldDelegate.color != color;
}

/// Hairline ink along a torn [edge], drawn above the clipped sheet.
class TornEdgeStrokePainter extends CustomPainter {
  final int seed;
  final double amplitude;
  final TornEdge edge;
  final Color color;

  const TornEdgeStrokePainter({
    required this.seed,
    this.amplitude = 5.0,
    this.edge = TornEdge.left,
    this.color = const Color(0x2A3A3835),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tear = buildTornEdgePolyline(
      size: size,
      seed: seed,
      edge: edge,
      amplitude: amplitude,
    );
    final hairline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..isAntiAlias = true;
    canvas.drawPath(tear, hairline);
  }

  @override
  bool shouldRepaint(covariant TornEdgeStrokePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.edge != edge ||
      oldDelegate.color != color;
}
