import 'package:flutter/material.dart';

import '../models/stroke.dart';
import '../../data/ink_renderer.dart';
import '../models/canvas_smart_models.dart';

/// Uniform hash-grid spatial index over stroke AABBs.
///
/// Cell size is in world units. Used for viewport culling and eraser/lasso
/// queries so we don't scan every stroke on large infinite canvases.
class StrokeSpatialIndex {
  StrokeSpatialIndex({this.cellSize = 1024.0});

  final double cellSize;

  final Map<String, Rect> _bounds = {};
  final Map<(int, int), Set<String>> _cells = {};

  Rect? get contentBounds {
    if (_bounds.isEmpty) return null;
    Rect? union;
    for (final b in _bounds.values) {
      union = union == null ? b : union.expandToInclude(b);
    }
    return union;
  }

  void clear() {
    _bounds.clear();
    _cells.clear();
  }

  void rebuild(List<Stroke> strokes) {
    clear();
    for (final s in strokes) {
      if (s.isHidden) continue;
      insert(s);
    }
  }

  void insert(Stroke stroke) {
    remove(stroke.id);
    final bounds = _boundsOf(stroke);
    if (bounds == null) return;
    _bounds[stroke.id] = bounds;
    for (final key in _cellKeys(bounds)) {
      _cells.putIfAbsent(key, () => <String>{}).add(stroke.id);
    }
  }

  void remove(String id) {
    final bounds = _bounds.remove(id);
    if (bounds == null) return;
    for (final key in _cellKeys(bounds)) {
      final set = _cells[key];
      if (set == null) continue;
      set.remove(id);
      if (set.isEmpty) _cells.remove(key);
    }
  }

  /// Stroke ids whose bounds intersect [region] (may include false positives
  /// at cell granularity — callers should still check exact bounds).
  Set<String> query(Rect region) {
    final result = <String>{};
    for (final key in _cellKeys(region)) {
      final set = _cells[key];
      if (set != null) result.addAll(set);
    }
    return result;
  }

  /// Strokes whose cached bounds intersect [region].
  List<Stroke> queryStrokes(List<Stroke> all, Rect region) {
    final ids = query(region);
    if (ids.isEmpty) return const [];
    final out = <Stroke>[];
    for (final s in all) {
      if (!ids.contains(s.id) || s.isHidden) continue;
      final b = _bounds[s.id];
      if (b != null && b.overlaps(region)) out.add(s);
    }
    return out;
  }

  Rect? boundsOf(String id) => _bounds[id];

  Iterable<(int, int)> _cellKeys(Rect r) sync* {
    final minCx = (r.left / cellSize).floor();
    final maxCx = (r.right / cellSize).floor();
    final minCy = (r.top / cellSize).floor();
    final maxCy = (r.bottom / cellSize).floor();
    for (var cx = minCx; cx <= maxCx; cx++) {
      for (var cy = minCy; cy <= maxCy; cy++) {
        yield (cx, cy);
      }
    }
  }

  static Rect? _boundsOf(Stroke stroke) {
    if (stroke.shapeType != ShapeType.none &&
        stroke.shapeVertices.isNotEmpty) {
      final v = stroke.shapeVertices;
      double? minX, minY, maxX, maxY;
      for (var i = 0; i + 1 < v.length; i += 2) {
        final x = v[i];
        final y = v[i + 1];
        minX = minX == null ? x : (x < minX ? x : minX);
        minY = minY == null ? y : (y < minY ? y : minY);
        maxX = maxX == null ? x : (x > maxX ? x : maxX);
        maxY = maxY == null ? y : (y > maxY ? y : maxY);
      }
      if (minX == null) return null;
      return Rect.fromLTRB(minX, minY!, maxX!, maxY!)
          .inflate(stroke.baseWidth);
    }
    if (stroke.points.isEmpty) return null;
    return InkRenderer.boundsOf(stroke.points, pad: stroke.baseWidth);
  }
}
