import 'dart:math' as math;
import 'dart:ui';

import '../models/canvas_smart_models.dart';
import '../models/stroke.dart';

/// Axis-aligned bounds for geometry (no stroke-width pad).
Rect strokeWorldBounds(Stroke stroke) {
  if (stroke.shapeType != ShapeType.none && stroke.shapeVertices.length >= 4) {
    final v = stroke.shapeVertices;
    var minX = v[0];
    var maxX = v[0];
    var minY = v[1];
    var maxY = v[1];
    for (var i = 0; i + 1 < v.length; i += 2) {
      final x = v[i];
      final y = v[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
  if (stroke.points.isEmpty) return Rect.zero;
  var minX = stroke.points.first.x;
  var maxX = stroke.points.first.x;
  var minY = stroke.points.first.y;
  var maxY = stroke.points.first.y;
  for (final p in stroke.points) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

int strokeEndTime(Stroke stroke) {
  if (stroke.points.isEmpty) return 0;
  return stroke.points.last.timestamp;
}

/// Visible ink that the calculator should consider.
bool isCalcInk(Stroke stroke) {
  return !stroke.isHidden &&
      !stroke.isHighlighter &&
      !stroke.isTape &&
      stroke.points.isNotEmpty;
}

/// A short, flat, roughly horizontal stroke (minus, equals bar, fraction bar).
bool isHorizontalBar(Stroke stroke, {double minWidth = 10}) {
  final b = strokeWorldBounds(stroke);
  if (b.width < minWidth) return false;
  final height = math.max(b.height, 1.0);
  if (b.width / height < 2.2) return false;

  Offset? start;
  Offset? end;
  if (stroke.shapeType == ShapeType.line && stroke.shapeVertices.length >= 4) {
    start = Offset(stroke.shapeVertices[0], stroke.shapeVertices[1]);
    end = Offset(
      stroke.shapeVertices[stroke.shapeVertices.length - 2],
      stroke.shapeVertices[stroke.shapeVertices.length - 1],
    );
  } else if (stroke.points.length >= 2) {
    start = Offset(stroke.points.first.x, stroke.points.first.y);
    end = Offset(stroke.points.last.x, stroke.points.last.y);
  }
  if (start != null && end != null) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    if (dx < 1) return false;
    // ~25 degrees
    if (dy / dx > 0.47) return false;
  }

  return height / b.width <= 0.45;
}

/// A tall, thin, roughly vertical stroke (plus stem, digit 1).
bool isVerticalBar(Stroke stroke, {double minHeight = 10}) {
  final b = strokeWorldBounds(stroke);
  if (b.height < minHeight) return false;
  final width = math.max(b.width, 1.0);
  if (b.height / width < 1.8) return false;

  Offset? start;
  Offset? end;
  if (stroke.shapeType == ShapeType.line && stroke.shapeVertices.length >= 4) {
    start = Offset(stroke.shapeVertices[0], stroke.shapeVertices[1]);
    end = Offset(
      stroke.shapeVertices[stroke.shapeVertices.length - 2],
      stroke.shapeVertices[stroke.shapeVertices.length - 1],
    );
  } else if (stroke.points.length >= 2) {
    start = Offset(stroke.points.first.x, stroke.points.first.y);
    end = Offset(stroke.points.last.x, stroke.points.last.y);
  }
  if (start != null && end != null) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    if (dy < 1) return false;
    if (dx / dy > 0.55) return false;
  }

  return width / b.height <= 0.55;
}

/// A geometrically detected `+` or binary `-` in an expression.
class InkOperator {
  final String symbol;
  final Rect bounds;
  final List<Stroke> strokes;

  const InkOperator({
    required this.symbol,
    required this.bounds,
    required this.strokes,
  });

  Set<String> get strokeIds => {for (final s in strokes) s.id};
}

/// Find `+` and binary `-` from stroke shape, not ML Kit.
///
/// A plus is a horizontal bar crossed near its middle by a vertical stem.
/// ML Kit's English model almost always reads that crossbar as minus.
List<InkOperator> detectArithmeticOperators(List<Stroke> strokes) {
  if (strokes.length < 3) return const [];
  final used = <String>{};
  final ops = <InkOperator>[];

  final pluses = _findPlusSigns(strokes);
  for (final plus in pluses) {
    ops.add(plus);
    used.addAll(plus.strokeIds);
  }

  for (final s in strokes) {
    if (used.contains(s.id)) continue;
    if (!_isBinaryMinus(s, strokes, used)) continue;
    final b = strokeWorldBounds(s);
    ops.add(InkOperator(symbol: '-', bounds: b, strokes: [s]));
    used.add(s.id);
  }

  ops.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));
  return ops;
}

/// Remaining ink, grouped left-to-right between [ops].
List<List<Stroke>> splitOperands(
  List<Stroke> strokes,
  List<InkOperator> ops,
) {
  if (ops.isEmpty) return [strokes];
  final opIds = {for (final o in ops) ...o.strokeIds};
  final rest = [for (final s in strokes) if (!opIds.contains(s.id)) s];
  final buckets = List<List<Stroke>>.generate(ops.length + 1, (_) => []);
  for (final s in rest) {
    final x = strokeWorldBounds(s).center.dx;
    var slot = ops.length;
    for (var i = 0; i < ops.length; i++) {
      if (x < ops[i].bounds.center.dx) {
        slot = i;
        break;
      }
    }
    buckets[slot].add(s);
  }
  return buckets;
}

List<InkOperator> _findPlusSigns(List<Stroke> strokes) {
  final items = [
    for (final s in strokes) (s: s, b: strokeWorldBounds(s)),
  ];
  final used = <String>{};
  final out = <InkOperator>[];

  for (final bar in items) {
    if (used.contains(bar.s.id)) continue;
    if (bar.b.width < 6) continue;
    if (bar.b.width / math.max(bar.b.height, 1) < 1.2) continue;

    Stroke? stem;
    var best = double.infinity;
    for (final other in items) {
      if (other.s.id == bar.s.id || used.contains(other.s.id)) continue;
      if (!_couldBePlusStem(bar.b, other.b)) continue;
      // Leftmost / rightmost ink is an operand (e.g. a "1"), not the stem.
      final leftmost = items.every(
        (o) => o.s.id == other.s.id || o.b.center.dx >= other.b.center.dx,
      );
      final rightmost = items.every(
        (o) => o.s.id == other.s.id || o.b.center.dx <= other.b.center.dx,
      );
      if (leftmost || rightmost) continue;
      // Multi-stroke digits (5, 4, 6) sit beside the minus; their extra
      // stroke must not be stolen as a plus stem.
      if (_stemBelongsToDigit(bar.b, other.b, items, other.s.id, bar.s.id)) {
        continue;
      }
      final score = (other.b.center.dx - bar.b.center.dx).abs();
      if (score < best) {
        best = score;
        stem = other.s;
      }
    }
    if (stem == null) continue;
    final stemBounds = strokeWorldBounds(stem);
    final plusBounds = bar.b.expandToInclude(stemBounds);
    final hasLeft = items.any(
      (o) =>
          o.s.id != bar.s.id &&
          o.s.id != stem!.id &&
          o.b.center.dx < plusBounds.left - 2,
    );
    final hasRight = items.any(
      (o) =>
          o.s.id != bar.s.id &&
          o.s.id != stem!.id &&
          o.b.center.dx > plusBounds.right + 2,
    );
    if (!hasLeft || !hasRight) continue;
    used.add(bar.s.id);
    used.add(stem.id);
    out.add(InkOperator(
      symbol: '+',
      bounds: bar.b.expandToInclude(strokeWorldBounds(stem)),
      strokes: [bar.s, stem],
    ));
  }
  return out;
}

/// Stem may sit beside the bar with a gap — common when the expression is
/// written with extra spacing.
bool _couldBePlusStem(Rect bar, Rect stem) {
  if (stem.height < bar.height * 0.85 &&
      stem.height / math.max(stem.width, 1) < 1.05) {
    return false;
  }
  // A second flat bar (5's hat, another minus) is not a stem.
  if (stem.width / math.max(stem.height, 1) >= 1.4) return false;
  if (stem.width > bar.width * 1.8) return false;
  final dx = (stem.center.dx - bar.center.dx).abs();
  if (dx > math.max(bar.width, 12) * 1.6) return false;
  if (stem.bottom < bar.top - 10) return false;
  if (stem.top > bar.bottom + 10) return false;
  return true;
}

/// True when [stem] is part of a digit on one side of [bar], e.g. the
/// vertical of a "5" sitting to the right of a minus.
bool _stemBelongsToDigit(
  Rect bar,
  Rect stem,
  List<({Stroke s, Rect b})> items,
  String stemId,
  String barId,
) {
  final side = stem.center.dx < bar.left
      ? -1
      : stem.center.dx > bar.right
          ? 1
          : 0;
  if (side == 0) return false;
  for (final other in items) {
    if (other.s.id == stemId || other.s.id == barId) continue;
    final otherSide = other.b.center.dx < bar.left
        ? -1
        : other.b.center.dx > bar.right
            ? 1
            : 0;
    if (otherSide != side) continue;
    final overlap = math.min(stem.right, other.b.right) -
        math.max(stem.left, other.b.left);
    final minW = math.min(stem.width, other.b.width);
    if (overlap > math.max(0.5, minW * 0.1)) {
      return true;
    }
  }
  return false;
}

bool _isBinaryMinus(Stroke bar, List<Stroke> all, Set<String> used) {
  if (!isHorizontalBar(bar, minWidth: 8)) return false;
  final bb = strokeWorldBounds(bar);
  for (final s in all) {
    if (s.id == bar.id || used.contains(s.id)) continue;
    final b = strokeWorldBounds(s);
    final xOverlap = math.min(bb.right, b.right) - math.max(bb.left, b.left);
    final yOverlap = math.min(bb.bottom, b.bottom) - math.max(bb.top, b.top);
    if (xOverlap > bb.width * 0.15 &&
        yOverlap > 1 &&
        b.height > bb.height * 1.15 &&
        b.center.dx > bb.left - bb.width * 0.4 &&
        b.center.dx < bb.right + bb.width * 0.4) {
      return false;
    }
  }
  var left = false;
  var right = false;
  final reach = bb.width * 3.5;
  for (final s in all) {
    if (s.id == bar.id || used.contains(s.id)) continue;
    final b = strokeWorldBounds(s);
    if (b.center.dx < bb.left && bb.left - b.right < reach) left = true;
    if (b.center.dx > bb.right && b.left - bb.right < reach) right = true;
  }
  return left && right;
}

/// Strokes whose x-ranges overlap belong to the same glyph.
/// Plus signs are kept as their own glyph so the stem is not eaten by a digit.
List<List<Stroke>> groupGlyphs(List<Stroke> strokes) {
  if (strokes.isEmpty) return const [];
  final pluses = _findPlusSigns(strokes);
  final plusIds = {for (final p in pluses) ...p.strokeIds};
  final rest = [for (final s in strokes) if (!plusIds.contains(s.id)) s];

  final groups = <List<Stroke>>[];
  if (rest.isNotEmpty) {
    final items = [
      for (final s in rest) (stroke: s, bounds: strokeWorldBounds(s)),
    ]..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));

    var current = <Stroke>[items.first.stroke];
    var currentBounds = items.first.bounds;

    for (var i = 1; i < items.length; i++) {
      final next = items[i];
      final overlap = math.min(currentBounds.right, next.bounds.right) -
          math.max(currentBounds.left, next.bounds.left);
      final minW = math.min(currentBounds.width, next.bounds.width);
      if (overlap > math.max(2.0, minW * 0.12)) {
        current.add(next.stroke);
        currentBounds = currentBounds.expandToInclude(next.bounds);
      } else {
        groups.add(current);
        current = [next.stroke];
        currentBounds = next.bounds;
      }
    }
    groups.add(current);
  }

  for (final plus in pluses) {
    groups.add(plus.strokes);
  }
  groups.sort((a, b) {
    final la = unionBounds(a.map(strokeWorldBounds)).left;
    final lb = unionBounds(b.map(strokeWorldBounds)).left;
    return la.compareTo(lb);
  });
  return groups;
}

Rect unionBounds(Iterable<Rect> rects) {
  Rect? u;
  for (final r in rects) {
    if (r.isEmpty) continue;
    u = u == null ? r : u.expandToInclude(r);
  }
  return u ?? Rect.zero;
}

/// True when a long bar in [strokes] has ink both above and below it.
bool looksLikeStackedFraction(List<Stroke> strokes) {
  if (strokes.length < 3) return false;
  final boundsById = {
    for (final s in strokes) s.id: strokeWorldBounds(s),
  };

  for (final bar in strokes) {
    if (!isHorizontalBar(bar, minWidth: 16)) continue;
    final barB = boundsById[bar.id]!;
    var above = false;
    var below = false;
    for (final other in strokes) {
      if (other.id == bar.id) continue;
      final b = boundsById[other.id]!;
      final overlap = math.min(barB.right, b.right) - math.max(barB.left, b.left);
      if (overlap < barB.width * 0.2) continue;
      if (b.bottom <= barB.center.dy && b.center.dy < barB.top + 2) {
        above = true;
      } else if (b.center.dy < barB.top) {
        above = true;
      }
      if (b.top >= barB.center.dy && b.center.dy > barB.bottom - 2) {
        below = true;
      } else if (b.center.dy > barB.bottom) {
        below = true;
      }
    }
    if (above && below) return true;
  }
  return false;
}

/// Glyphs that sit clearly above the writing baseline and are smaller.
Set<int> superscriptGlyphIndexes(List<List<Stroke>> glyphs) {
  if (glyphs.length < 2) return {};
  final glyphBounds = [
    for (final g in glyphs)
      unionBounds(g.map(strokeWorldBounds)),
  ];
  final heights = glyphBounds.map((b) => b.height).where((h) => h > 4).toList()
    ..sort();
  if (heights.isEmpty) return {};
  final medianH = heights[heights.length ~/ 2];
  final bottoms = glyphBounds.map((b) => b.bottom).toList()..sort();
  final baseline = bottoms[bottoms.length ~/ 2];

  final out = <int>{};
  for (var i = 0; i < glyphBounds.length; i++) {
    final b = glyphBounds[i];
    // Minus/plus bars sit on the midline and must not become exponents.
    if (b.width / math.max(b.height, 1) >= 2.0) continue;
    final raised = (baseline - b.bottom) > medianH * 0.28 &&
        b.center.dy < baseline - medianH * 0.35;
    final small = b.height <= medianH * 0.9;
    if (raised && small) out.add(i);
  }
  return out;
}
