import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models/stroke.dart';
import '../domain/models/canvas_smart_models.dart';

// ─────────────────────────────────────────────────────────────────
// Shape recognition engine — fully offline, no external packages
// Uses geometric heuristics:
//   Line       → points lie close to the segment through endpoints
//   Circle     → closed path with roughly constant radius from centroid
//   Oval       → same but asymmetric bounding box
//   Rectangle  → majority of points lie near 4 edges; ~right angles
//   Square     → rectangle with aspect ratio ≈ 1
//   Triangle   → closed path with exactly 3 detected corners
// ─────────────────────────────────────────────────────────────────
class SmartShapeRecognizer {
  /// Returns recognised ShapeType (or ShapeType.none) and the
  /// key vertex coordinates as a flat [x0,y0, x1,y1, ...] list.
  ShapeRecognitionResult recognize(List<StrokePoint> pts) {
    if (pts.length < 8) return ShapeRecognitionResult.none();

    final offsets = pts.map((p) => Offset(p.x, p.y)).toList();
    final bounds  = _bounds(offsets);
    if (bounds.width < 8 || bounds.height < 8) return ShapeRecognitionResult.none();

    if (_isLine(offsets, bounds)) {
      return ShapeRecognitionResult(
        type: ShapeType.line,
        vertices: [pts.first.x, pts.first.y, pts.last.x, pts.last.y],
        bounds: bounds,
      );
    }

    if (_isCircleOrOval(offsets, bounds)) {
      final ar = bounds.width / bounds.height;
      final type = (ar > 0.8 && ar < 1.25) ? ShapeType.circle : ShapeType.oval;
      return ShapeRecognitionResult(
        type: type,
        vertices: [bounds.left, bounds.top, bounds.right, bounds.bottom],
        bounds: bounds,
      );
    }

    if (_isTriangle(offsets, bounds)) {
      final verts = _triangleVertices(offsets, bounds);
      return ShapeRecognitionResult(
        type: ShapeType.triangle,
        vertices: verts.expand((o) => [o.dx, o.dy]).toList(),
        bounds: bounds,
      );
    }

    if (_isRectOrSquare(offsets, bounds)) {
      final ar = bounds.width / bounds.height;
      final type = (ar > 0.82 && ar < 1.22) ? ShapeType.square : ShapeType.rectangle;
      return ShapeRecognitionResult(
        type: type,
        vertices: [bounds.left, bounds.top, bounds.right, bounds.bottom],
        bounds: bounds,
      );
    }

    return ShapeRecognitionResult.none();
  }

  // ── Heuristic implementations ────────────────────────────────

  Rect _bounds(List<Offset> pts) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;   if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;   if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _isLine(List<Offset> pts, Rect bounds) {
    final s = pts.first, e = pts.last;
    final len = (e - s).distance;
    if (len < 20) return false;
    final thr = math.max(10.0, len * 0.07);
    final dx = e.dx - s.dx, dy = e.dy - s.dy;
    for (final p in pts) {
      final d = ((dy * p.dx - dx * p.dy + e.dx * s.dy - e.dy * s.dx) / len).abs();
      if (d > thr) return false;
    }
    return true;
  }

  bool _isCircleOrOval(List<Offset> pts, Rect bounds) {
    // Path must be closed
    final startEnd = (pts.first - pts.last).distance;
    final diag = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    if (startEnd > diag * 0.3) return false;

    final center = bounds.center;
    final radii = pts.map((p) => (p - center).distance).toList();
    final mean = radii.reduce((a, b) => a + b) / radii.length;
    if (mean < 12) return false;
    final variance = radii.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) / radii.length;
    return math.sqrt(variance) / mean < 0.22;
  }

  bool _isTriangle(List<Offset> pts, Rect bounds) {
    final corners  = _corners(pts);
    final startEnd = (pts.first - pts.last).distance;
    final diag = math.sqrt(bounds.width * bounds.width + bounds.height * bounds.height);
    return corners.length == 3 && startEnd < diag * 0.3;
  }

  bool _isRectOrSquare(List<Offset> pts, Rect bounds) {
    final thr = math.min(bounds.width, bounds.height) * 0.18;
    int onEdge = 0;
    for (final p in pts) {
      if ((p.dx - bounds.left).abs()   < thr ||
          (p.dx - bounds.right).abs()  < thr ||
          (p.dy - bounds.top).abs()    < thr ||
          (p.dy - bounds.bottom).abs() < thr) {
        onEdge++;
      }
    }
    return onEdge / pts.length > 0.72;
  }

  List<Offset> _corners(List<Offset> pts) {
    final result = <Offset>[];
    final step   = math.max(1, pts.length ~/ 25);
    for (int i = step; i < pts.length - step; i += step) {
      final prev = pts[math.max(0, i - step)];
      final curr = pts[i];
      final next = pts[math.min(pts.length - 1, i + step)];
      final v1 = curr - prev, v2 = next - curr;
      if (v1.distance < 1 || v2.distance < 1) continue;
      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
      if (dot < 0.25) { result.add(curr); i += step * 2; }
    }
    return result;
  }

  List<Offset> _triangleVertices(List<Offset> pts, Rect b) {
    final c = _corners(pts);
    if (c.length >= 3) return c.take(3).toList();
    return [Offset(b.center.dx, b.top), b.bottomLeft, b.bottomRight];
  }
}

// ─────────────────────────────────────────────────────────────────
// Result container
// ─────────────────────────────────────────────────────────────────
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
