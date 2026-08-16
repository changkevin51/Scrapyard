import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import '../domain/models/stroke.dart';
import '../domain/models/canvas_smart_models.dart';

/// Shape recognition: $1 unistroke templates for lines / triangles / stars,
/// plus circularity to split circles from squares.
///
/// $1 alone cannot tell those two apart — it scale-normalizes every stroke
/// into a square, so a circle and a square become similar closed loops.
/// `4π·area / perimeter²` is ~1.0 for a circle and ~0.785 for a square.
class SmartShapeRecognizer {
  static const _minScore = 0.62;
  static const _shapeToolMinScore = 0.52;
  static const _polygonScore = 0.70;
  static const _squareAspect = 0.88;
  static const _circleCircularity = 0.86;

  ShapeRecognitionResult recognize(
    List<StrokePoint> pts, {
    bool fromShapeTool = false,
  }) {
    if (pts.length < 8) return ShapeRecognitionResult.none();

    final offsets = _densify([for (final p in pts) Offset(p.x, p.y)]);
    final recognized = recognizeUnistroke(offsets);
    final minScore = fromShapeTool ? _shapeToolMinScore : _minScore;
    final name = (recognized != null && recognized.score >= minScore)
        ? recognized.name
        : null;

    if (name == DefaultUnistrokeNames.line) {
      final (start, end) = recognized!.convertToLine();
      if ((end - start).distance < 20) return ShapeRecognitionResult.none();
      return ShapeRecognitionResult(
        type: ShapeType.line,
        vertices: [start.dx, start.dy, end.dx, end.dy],
        bounds: recognized.convertToRect(),
      );
    }

    if (name == DefaultUnistrokeNames.triangle &&
        recognized!.score >= _polygonScore) {
      final poly = recognized.convertToCanonicalPolygon();
      final verts = _uniqueClosedVertices(poly);
      if (verts.length >= 3) {
        return ShapeRecognitionResult(
          type: ShapeType.triangle,
          vertices: verts.take(3).expand((o) => [o.dx, o.dy]).toList(),
          bounds: recognized.convertToRect(),
        );
      }
    }

    if (name == DefaultUnistrokeNames.star &&
        recognized!.score >= _polygonScore) {
      final poly = recognized.convertToCanonicalPolygon();
      if (poly.length >= 5) {
        return ShapeRecognitionResult(
          type: ShapeType.star,
          vertices: poly.expand((o) => [o.dx, o.dy]).toList(),
          bounds: recognized.convertToRect(),
        );
      }
    }

    final closed = _isClosed(offsets);
    final circleOrRect = name == DefaultUnistrokeNames.circle ||
        name == DefaultUnistrokeNames.rectangle;
    if (circleOrRect) return _circleOrQuad(offsets);

    // Shape tool: still snap a clearly round closed stroke if $1 abstains.
    if (fromShapeTool && closed && _circularity(offsets) >= 0.74) {
      return _circleOrQuad(offsets);
    }

    return ShapeRecognitionResult.none();
  }

  ShapeRecognitionResult _circleOrQuad(List<Offset> pts) {
    final bounds = _bounds(pts);
    if (bounds.width < 8 || bounds.height < 8) {
      return ShapeRecognitionResult.none();
    }

    if (_isDiamond(pts, bounds)) {
      final c = bounds.center;
      return ShapeRecognitionResult(
        type: ShapeType.diamond,
        vertices: [
          c.dx,
          bounds.top,
          bounds.right,
          c.dy,
          c.dx,
          bounds.bottom,
          bounds.left,
          c.dy,
        ],
        bounds: bounds,
      );
    }

    final circularity = _circularity(pts);
    final ar = _aspect(bounds);
    final isometric = ar >= _squareAspect && ar <= 1 / _squareAspect;
    // Elongated ellipses score ~0.80; elongated rectangles ~0.67.
    final circleCut = isometric ? _circleCircularity : 0.74;

    if (circularity >= circleCut) {
      if (isometric) {
        final r = (bounds.width + bounds.height) / 4;
        final c = bounds.center;
        return ShapeRecognitionResult(
          type: ShapeType.circle,
          vertices: [c.dx - r, c.dy - r, c.dx + r, c.dy + r],
          bounds: bounds,
        );
      }
      return ShapeRecognitionResult(
        type: ShapeType.oval,
        vertices: [bounds.left, bounds.top, bounds.right, bounds.bottom],
        bounds: bounds,
      );
    }

    final type = (ar >= _squareAspect && ar <= 1 / _squareAspect)
        ? ShapeType.square
        : ShapeType.rectangle;
    return ShapeRecognitionResult(
      type: type,
      vertices: [bounds.left, bounds.top, bounds.right, bounds.bottom],
      bounds: bounds,
    );
  }

  bool _isClosed(List<Offset> pts) {
    final bounds = _bounds(pts);
    final diag = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    return (pts.first - pts.last).distance < diag * 0.28;
  }

  double _circularity(List<Offset> pts) {
    final ring = _closedRing(pts);
    var peri = 0.0;
    var area2 = 0.0;
    for (int i = 0; i < ring.length - 1; i++) {
      final a = ring[i];
      final b = ring[i + 1];
      peri += (b - a).distance;
      area2 += a.dx * b.dy - b.dx * a.dy;
    }
    if (peri < 1) return 0;
    final area = area2.abs() / 2;
    return (4 * math.pi * area) / (peri * peri);
  }

  List<Offset> _closedRing(List<Offset> pts) {
    if (pts.length < 2) return pts;
    if ((pts.first - pts.last).distance < 4) return pts;
    return [...pts, pts.first];
  }

  Rect _bounds(List<Offset> pts) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _aspect(Rect bounds) {
    if (bounds.height < 1) return 999;
    return bounds.width / bounds.height;
  }

  /// $1 is rotation-invariant, so a diamond matches the rectangle template.
  /// Ink that hugs the AABB midpoints (not the corners) is a diamond.
  bool _isDiamond(List<Offset> pts, Rect bounds) {
    final hw = bounds.width / 2;
    final hh = bounds.height / 2;
    if (hw < 8 || hh < 8) return false;

    final c = bounds.center;
    final diamond = [
      Offset(c.dx, bounds.top),
      Offset(bounds.right, c.dy),
      Offset(c.dx, bounds.bottom),
      Offset(bounds.left, c.dy),
    ];
    final thr = math.min(hw, hh) * 0.22;

    int nearDiamond = 0;
    int nearRect = 0;
    for (final p in pts) {
      if (_distToEdges(p, diamond) < thr) nearDiamond++;
      if (_distToRectEdges(p, bounds) < thr) nearRect++;
    }
    return nearDiamond > nearRect * 1.2 && nearDiamond / pts.length > 0.62;
  }

  double _distToRectEdges(Offset p, Rect r) {
    final dx = math.max(0, math.max(r.left - p.dx, p.dx - r.right));
    final dy = math.max(0, math.max(r.top - p.dy, p.dy - r.bottom));
    if (dx == 0 && dy == 0) {
      return math.min(
        math.min((p.dx - r.left).abs(), (p.dx - r.right).abs()),
        math.min((p.dy - r.top).abs(), (p.dy - r.bottom).abs()),
      );
    }
    return math.sqrt(dx * dx + dy * dy);
  }

  double _distToEdges(Offset p, List<Offset> poly) {
    var best = double.infinity;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final d = _distToSegment(p, a, b);
      if (d < best) best = d;
    }
    return best;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-6) return (p - a).distance;
    var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// The $1 engine needs 64 samples. Short stylus strokes are densified
  /// along the path so a quick circle still matches.
  List<Offset> _densify(List<Offset> pts) {
    const need = 64;
    if (pts.length >= need) return pts;

    var total = 0.0;
    for (int i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    if (total < 8) return pts;

    final out = <Offset>[pts.first];
    final step = total / (need - 1);
    var walked = 0.0;
    var emitAt = step;
    for (int i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final seg = (b - a).distance;
      while (walked + seg >= emitAt && out.length < need - 1) {
        final t = ((emitAt - walked) / seg).clamp(0.0, 1.0);
        out.add(Offset.lerp(a, b, t)!);
        emitAt += step;
      }
      walked += seg;
    }
    out.add(pts.last);
    return out;
  }

  List<Offset> _uniqueClosedVertices(List<Offset> poly) {
    if (poly.isEmpty) return const [];
    final out = <Offset>[poly.first];
    const eps = 4.0;
    for (final p in poly.skip(1)) {
      if ((p - out.last).distance > eps) out.add(p);
    }
    if (out.length > 1 && (out.first - out.last).distance < eps) {
      out.removeLast();
    }
    return out;
  }
}

class ShapeRecognitionResult {
  final ShapeType type;
  final List<double> vertices; // flat [x0,y0, x1,y1, ...]
  final Rect bounds;

  const ShapeRecognitionResult({
    required this.type,
    required this.vertices,
    required this.bounds,
  });

  factory ShapeRecognitionResult.none() => const ShapeRecognitionResult(
        type: ShapeType.none,
        vertices: [],
        bounds: Rect.zero,
      );

  bool get recognized => type != ShapeType.none;
}
