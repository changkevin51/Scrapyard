import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';
import 'ink_geometry.dart';

/// A geometrically detected `=` plus the ink to its left.
class EqualsDetection {
  final Stroke topBar;
  final Stroke bottomBar;
  final Rect equalsBounds;
  final List<Stroke> expressionStrokes;
  final Rect expressionBounds;

  const EqualsDetection({
    required this.topBar,
    required this.bottomBar,
    required this.equalsBounds,
    required this.expressionStrokes,
    required this.expressionBounds,
  });

  Set<String> get equalsStrokeIds => {topBar.id, bottomBar.id};

  Set<String> get expressionStrokeIds => {
        for (final s in expressionStrokes) s.id,
      };

  String get pairKey {
    final ids = equalsStrokeIds.toList()..sort();
    return ids.join('|');
  }

  Color get color => topBar.color;
}

/// Detect an equals sign in [strokes].
///
/// When [involvingStrokeId] is set, that stroke must be one of the two bars
/// (the usual case: the user just finished drawing `=`).
EqualsDetection? detectEquals(
  List<Stroke> strokes, {
  String? involvingStrokeId,
  Set<String> ignoredIds = const {},
  bool lenient = false,
}) {
  final ink = [
    for (final s in strokes)
      if (isCalcInk(s) && !ignoredIds.contains(s.id)) s,
  ];
  if (ink.length < 3) return null;

  final bars = [
    for (final s in ink)
      if (isHorizontalBar(s)) s,
  ];
  if (bars.length < 2) return null;

  Stroke? required;
  if (involvingStrokeId != null) {
    for (final s in bars) {
      if (s.id == involvingStrokeId) {
        required = s;
        break;
      }
    }
    if (required == null) return null;
  }

  final pairs = <_BarPair>[];
  if (required != null) {
    for (final other in bars) {
      if (other.id == required.id) continue;
      final pair = _asEqualsPair(required, other);
      if (pair != null) pairs.add(pair);
    }
  } else {
    for (var i = 0; i < bars.length; i++) {
      for (var j = i + 1; j < bars.length; j++) {
        final pair = _asEqualsPair(bars[i], bars[j]);
        if (pair != null) pairs.add(pair);
      }
    }
  }
  if (pairs.isEmpty) return null;

  pairs.sort((a, b) {
    final recency = b.maxEnd.compareTo(a.maxEnd);
    if (recency != 0) return recency;
    return a.score.compareTo(b.score);
  });

  for (final pair in pairs) {
    final detection = _buildDetection(ink, pair, lenient: lenient);
    if (detection != null) return detection;
  }
  return null;
}

class _BarPair {
  final Stroke top;
  final Stroke bottom;
  final Rect bounds;
  final double score;
  final int maxEnd;

  _BarPair({
    required this.top,
    required this.bottom,
    required this.bounds,
    required this.score,
    required this.maxEnd,
  });
}

_BarPair? _asEqualsPair(Stroke a, Stroke b) {
  if (!_withinWritingWindow(a, b)) return null;

  final ba = strokeWorldBounds(a);
  final bb = strokeWorldBounds(b);
  final lenA = ba.width;
  final lenB = bb.width;
  final avgLen = (lenA + lenB) / 2;
  if (avgLen < 10) return null;

  final lengthRatio = lenA > lenB ? lenA / lenB : lenB / lenA;
  if (lengthRatio > 1.8) return null;

  final centerDx = (ba.center.dx - bb.center.dx).abs();
  if (centerDx > avgLen * 0.35) return null;

  final top = ba.center.dy <= bb.center.dy ? a : b;
  final bottom = identical(top, a) ? b : a;
  final topB = identical(top, a) ? ba : bb;
  final botB = identical(top, a) ? bb : ba;

  final innerGap = botB.top - topB.bottom;
  final centerGap = botB.center.dy - topB.center.dy;
  if (centerGap < avgLen * 0.12 || centerGap > avgLen * 0.95) return null;
  // Bars should be stacked, not overlapping into one thick minus.
  if (innerGap < -topB.height * 0.4) return null;

  final score = lengthRatio + centerDx / avgLen + (centerGap / avgLen - 0.4).abs();
  return _BarPair(
    top: top,
    bottom: bottom,
    bounds: topB.expandToInclude(botB),
    score: score,
    maxEnd: math.max(strokeEndTime(a), strokeEndTime(b)),
  );
}

bool _withinWritingWindow(Stroke a, Stroke b) {
  final ta = strokeEndTime(a);
  final tb = strokeEndTime(b);
  final dt = (ta - tb).abs();
  // Microseconds vs milliseconds — same heuristic as cluster detection.
  final isUs = math.max(ta, tb) > 5000000 || dt > 20000;
  final limit = isUs ? 4000000 : 4000; // ~4s
  return dt <= limit;
}

EqualsDetection? _buildDetection(
  List<Stroke> ink,
  _BarPair pair, {
  bool lenient = false,
}) {
  final equalsIds = {pair.top.id, pair.bottom.id};
  final eq = pair.bounds;
  final skip = {...equalsIds, ..._foreignEqualsBarIds(ink, equalsIds)};
  final linePad = math.max(eq.height * (lenient ? 2.4 : 1.5), lenient ? 32.0 : 20.0);

  final onLine = [
    for (final s in ink)
      if (!skip.contains(s.id))
        if (_onSameLine(strokeWorldBounds(s), eq, linePad)) s,
  ];

  var chained = _chainFromEquals(
    onLine,
    eq,
    rightward: false,
    maxGapFactor: lenient ? 3.0 : 1.8,
  );
  if (chained.isEmpty) {
    if (!lenient) return null;
    chained = _chainFromEquals(
      onLine,
      eq,
      rightward: false,
      maxGapFactor: 3.6,
    );
    if (chained.isEmpty) return null;
  }

  // Fractions / sqrts stack vertically. The left-to-right chain only keeps
  // strokes whose centers sit near the equals midline, so numerator,
  // denominator, and radical ink would otherwise be dropped (MathReader then
  // sees `\frac{2}` and fails grammar).
  final left = _attachStacked(ink, chained, skip, eq);
  if (left.isEmpty) return null;

  final hasGlyph = left.any((s) {
    final b = strokeWorldBounds(s);
    return b.height >= 8 && b.width / math.max(b.height, 1) < 2.2;
  });
  if (!hasGlyph && !lenient) return null;

  final right = _chainFromEquals(
    onLine,
    eq,
    rightward: true,
    maxGapFactor: lenient ? 2.4 : 1.6,
  );
  if (right.isNotEmpty && !lenient) return null;

  final exprBounds = unionBounds(left.map(strokeWorldBounds));
  if (exprBounds.isEmpty) return null;

  return EqualsDetection(
    topBar: pair.top,
    bottomBar: pair.bottom,
    equalsBounds: eq,
    expressionStrokes: left,
    expressionBounds: exprBounds,
  );
}

/// Other `=` pairs on the page must not be sent as minus/equals ink.
Set<String> _foreignEqualsBarIds(List<Stroke> ink, Set<String> currentPair) {
  final bars = [
    for (final s in ink)
      if (isHorizontalBar(s)) s,
  ];
  final ids = <String>{};
  for (var i = 0; i < bars.length; i++) {
    for (var j = i + 1; j < bars.length; j++) {
      final pair = _asEqualsPair(bars[i], bars[j]);
      if (pair == null) continue;
      if (currentPair.contains(pair.top.id) &&
          currentPair.contains(pair.bottom.id)) {
        continue;
      }
      ids.add(pair.top.id);
      ids.add(pair.bottom.id);
    }
  }
  return ids;
}

bool _onSameLine(Rect stroke, Rect equals, double pad) {
  final mid = equals.center.dy;
  return stroke.center.dy > mid - pad && stroke.center.dy < mid + pad;
}

List<Stroke> _chainFromEquals(
  List<Stroke> candidates,
  Rect equals, {
  required bool rightward,
  double maxGapFactor = 1.8,
}) {
  final remaining = [...candidates];
  final attached = <Stroke>[];
  var edge = rightward ? equals.right : equals.left;
  final unit = math.max(equals.width, 16.0);
  final maxGap = unit * maxGapFactor;

  var grew = true;
  while (grew) {
    grew = false;
    Stroke? best;
    var bestGap = double.infinity;
    for (final s in remaining) {
      final b = strokeWorldBounds(s);
      final gap = rightward ? (b.left - edge) : (edge - b.right);
      // Allow a plus stem to overlap the bar we just attached.
      if (gap < -unit * 1.5) continue;
      if (gap > maxGap) continue;
      if (rightward && b.center.dx < equals.center.dx) continue;
      if (!rightward && b.center.dx > equals.center.dx) continue;
      if (gap < bestGap) {
        bestGap = gap;
        best = s;
      }
    }
    if (best == null) break;
    attached.add(best);
    remaining.remove(best);
    final b = strokeWorldBounds(best);
    edge = rightward
        ? math.max(edge, b.right)
        : math.min(edge, b.left);
    grew = true;
  }

  attached.sort(
    (a, b) => strokeWorldBounds(a).left.compareTo(strokeWorldBounds(b).left),
  );
  return attached;
}

/// Grow [seed] with ink stacked above/below it (fraction num/den, sqrt).
///
/// Horizontal overlap is measured against the original seed, not the growing
/// blob, so a nearby equation on the page cannot flood-fill in.
List<Stroke> _attachStacked(
  List<Stroke> ink,
  List<Stroke> seed,
  Set<String> skipIds,
  Rect equals,
) {
  final attached = [...seed];
  final used = {for (final s in attached) s.id, ...skipIds};
  final seedBounds = unionBounds(seed.map(strokeWorldBounds));
  if (seedBounds.isEmpty) return attached;
  final maxVGap = math.max(
    math.max(seedBounds.height, equals.height) * 0.85,
    22.0,
  );

  var grew = true;
  while (grew) {
    grew = false;
    for (final s in ink) {
      if (used.contains(s.id)) continue;
      final b = strokeWorldBounds(s);
      if (b.center.dx > equals.center.dx) continue;

      final overlap = math.min(seedBounds.right, b.right) -
          math.max(seedBounds.left, b.left);
      final minW = math.min(seedBounds.width, b.width).clamp(1.0, 400.0);
      if (overlap < minW * 0.22) continue;

      final vGap = b.top > seedBounds.bottom
          ? b.top - seedBounds.bottom
          : seedBounds.top > b.bottom
              ? seedBounds.top - b.bottom
              : 0.0;
      if (vGap > maxVGap) continue;

      attached.add(s);
      used.add(s.id);
      grew = true;
    }
  }

  attached.sort(
    (a, b) => strokeWorldBounds(a).left.compareTo(strokeWorldBounds(b).left),
  );
  return attached;
}
