import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../data/pen_engine.dart';
import '../../domain/models/stroke.dart';

/// Screen-space eraser radius from the toolbar thickness dots (same as pen).
double eraserScreenRadius(double widthMod) => 10.0 * widthMod;

/// Sample along a drag so fast strokes don't skip ink.
List<Offset> sampleErasePath(Offset? last, Offset pos, double radius) {
  if (last == null) return [pos];
  final dist = (pos - last).distance;
  final steps = max(1, (dist / max(radius * 0.4, 2.0)).ceil());
  return [
    for (var i = 1; i <= steps; i++) Offset.lerp(last, pos, i / steps)!,
  ];
}

double distToSegmentSq(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distanceSquared;
  final t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final proj = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
  return (p - proj).distanceSquared;
}

/// True if [pos] is within [radius] of any point or segment in [pts].
bool pointsNearPoint(
  List<StrokePoint> pts,
  Offset pos, {
  required double radius,
}) {
  if (pts.isEmpty) return false;
  final r2 = radius * radius;
  for (var i = 0; i < pts.length; i++) {
    final a = Offset(pts[i].x, pts[i].y);
    if ((a - pos).distanceSquared <= r2) return true;
    if (i + 1 < pts.length) {
      final b = Offset(pts[i + 1].x, pts[i + 1].y);
      if (distToSegmentSq(pos, a, b) <= r2) return true;
    }
  }
  return false;
}

/// Carve [pts] under an eraser brush; returns surviving runs (length ≥ 2).
List<List<StrokePoint>> carveStrokePoints(
  List<StrokePoint> pts,
  Offset pos,
  double radius,
) {
  final r2 = radius * radius;
  final keptRuns = <List<StrokePoint>>[];
  var run = <StrokePoint>[];
  Offset? prevKept;

  for (final pt in pts) {
    final p = Offset(pt.x, pt.y);
    final inCircle = (p - pos).distanceSquared <= r2;
    final segmentCrosses =
        prevKept != null && distToSegmentSq(pos, prevKept, p) <= r2;

    if (inCircle) {
      if (run.length >= 2) keptRuns.add(run);
      run = [];
      prevKept = null;
    } else if (segmentCrosses) {
      if (run.length >= 2) keptRuns.add(run);
      run = [pt];
      prevKept = p;
    } else {
      run.add(pt);
      prevKept = p;
    }
  }
  if (run.length >= 2) keptRuns.add(run);
  return keptRuns;
}

/// Live eraser brush preview under the pointer.
class EraserPreviewState extends ChangeNotifier {
  Offset? _pos;
  double radius = 10;
  EraserMode mode = EraserMode.stroke;

  Offset? get pos => _pos;

  set pos(Offset? value) {
    if (value == null) {
      if (_pos == null) return;
      _pos = null;
      notifyListeners();
      return;
    }
    if (_pos != null && (_pos! - value).distanceSquared < 0.25) return;
    _pos = value;
    notifyListeners();
  }
}

class EraserPreviewPainter extends CustomPainter {
  final EraserPreviewState preview;
  final double radius;
  final EraserMode mode;

  EraserPreviewPainter({
    required this.preview,
    required this.radius,
    required this.mode,
  }) : super(repaint: preview);

  @override
  void paint(Canvas canvas, Size size) {
    final c = preview.pos;
    final r = preview.radius > 0 ? preview.radius : radius;
    if (c == null || r <= 0) return;
    final m = preview.mode;

    final fill = Paint()
      ..color = ScrapTheme.accent
          .withValues(alpha: m == EraserMode.area ? 0.12 : 0.07)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, r, fill);

    final ring = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = m == EraserMode.area ? 1.75 : 1.25;
    if (m == EraserMode.stroke) {
      _drawDashedCircle(canvas, c, r, ring);
    } else {
      canvas.drawCircle(c, r, ring);
    }

    final tick = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.7)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    const arm = 3.5;
    canvas.drawLine(c.translate(-arm, 0), c.translate(arm, 0), tick);
    canvas.drawLine(c.translate(0, -arm), c.translate(0, arm), tick);
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dashCount = 28;
    const dashFraction = 0.55;
    final path = Path();
    for (var i = 0; i < dashCount; i++) {
      final start = (i / dashCount) * 2 * pi;
      const sweep = (1 / dashCount) * 2 * pi * dashFraction;
      path.addArc(Rect.fromCircle(center: c, radius: r), start, sweep);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EraserPreviewPainter old) =>
      old.radius != radius || old.mode != mode;
}
