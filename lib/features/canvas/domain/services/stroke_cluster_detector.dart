import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// A detected group of strokes that likely form one expression / line.
class StrokeCluster {
  final String id;
  final Rect bounds;
  final Set<String> strokeIds;

  const StrokeCluster({
    required this.id,
    required this.bounds,
    required this.strokeIds,
  });
}

class _StrokeInfo {
  final String id;
  final Rect bounds;
  final int endTime;

  const _StrokeInfo({
    required this.id,
    required this.bounds,
    required this.endTime,
  });
}

class _UnionFind {
  final List<int> parent;
  final List<int> rank;

  _UnionFind(int n)
      : parent = List.generate(n, (i) => i),
        rank = List.filled(n, 0);

  int find(int x) {
    if (parent[x] != x) parent[x] = find(parent[x]);
    return parent[x];
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra == rb) return;
    if (rank[ra] < rank[rb]) {
      parent[ra] = rb;
    } else if (rank[ra] > rank[rb]) {
      parent[rb] = ra;
    } else {
      parent[rb] = ra;
      rank[ra]++;
    }
  }
}

/// Run cluster detection on a worker isolate.
///
/// [payload] is a list of maps with keys:
/// `id`, `left`, `top`, `right`, `bottom`, `endTime`.
Future<List<StrokeCluster>> detectClustersIsolate(
  List<Map<String, dynamic>> payload, {
  double canvasWidth = 1000,
}) {
  return Isolate.run(() {
    final infos = <_StrokeInfo>[
      for (final m in payload)
        _StrokeInfo(
          id: m['id'] as String,
          bounds: Rect.fromLTRB(
            (m['left'] as num).toDouble(),
            (m['top'] as num).toDouble(),
            (m['right'] as num).toDouble(),
            (m['bottom'] as num).toDouble(),
          ),
          endTime: m['endTime'] as int,
        ),
    ];
    return _detectFromInfos(infos, canvasWidth: canvasWidth);
  });
}

/// Detects line-level expression clusters from handwriting strokes using
/// spatial proximity modulated by writing timing.
List<StrokeCluster> detectClusters(
  List<Stroke> strokes, {
  double canvasWidth = 1000,
}) {
  final infos = <_StrokeInfo>[];
  for (final stroke in strokes) {
    if (stroke.isHidden || stroke.points.isEmpty) continue;
    infos.add(_StrokeInfo(
      id: stroke.id,
      bounds: _strokeBounds(stroke),
      endTime: stroke.points.last.timestamp,
    ));
  }
  return _detectFromInfos(infos, canvasWidth: canvasWidth);
}

List<StrokeCluster> _detectFromInfos(
  List<_StrokeInfo> infos, {
  double canvasWidth = 1000,
}) {
  if (infos.isEmpty) return const [];

  final unit = _estimateWritingUnit(infos);
  final uf = _UnionFind(infos.length);

  for (var i = 0; i < infos.length; i++) {
    for (var j = i + 1; j < infos.length; j++) {
      if (_shouldMerge(infos[i], infos[j], unit)) {
        uf.union(i, j);
      }
    }
  }

  final groups = <int, List<_StrokeInfo>>{};
  for (var i = 0; i < infos.length; i++) {
    final root = uf.find(i);
    groups.putIfAbsent(root, () => []).add(infos[i]);
  }

  final clusters = <StrokeCluster>[];
  for (final members in groups.values) {
    final bounds = _unionBounds(members.map((m) => m.bounds)).inflate(8);
    final strokeIds = members.map((m) => m.id).toSet();

    if (members.length == 1) {
      final b = members.first.bounds;
      if (b.width < 0.5 * unit && b.height < 0.5 * unit) continue;
    }

    if (bounds.width > canvasWidth * 0.7 && members.length < 3) continue;

    final sortedIds = strokeIds.toList()..sort();
    clusters.add(StrokeCluster(
      id: sortedIds.join('|').hashCode.toRadixString(16),
      bounds: bounds,
      strokeIds: strokeIds,
    ));
  }

  return clusters;
}

Rect _strokeBounds(Stroke stroke) {
  double minX = stroke.points.first.x;
  double maxX = stroke.points.first.x;
  double minY = stroke.points.first.y;
  double maxY = stroke.points.first.y;

  for (final point in stroke.points) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }

  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _estimateWritingUnit(List<_StrokeInfo> infos) {
  final heights = infos.map((i) => i.bounds.height).where((h) => h > 0).toList()
    ..sort();

  if (heights.isEmpty) return 24.0;

  final lo = (heights.length * 0.10).floor();
  final hi = math.max(lo + 1, (heights.length * 0.95).ceil());
  final trimmed = heights.sublist(lo, math.min(hi, heights.length));
  if (trimmed.isEmpty) return math.max(heights[heights.length ~/ 2], 12.0);

  final median = trimmed[trimmed.length ~/ 2];
  return math.max(median, 12.0);
}

bool _shouldMerge(_StrokeInfo a, _StrokeInfo b, double unit) {
  final timeGapRaw = (a.endTime - b.endTime).abs();
  // Timestamps may be microseconds (new) or milliseconds (legacy).
  final gapMs = timeGapRaw > 1000000000 ? timeGapRaw ~/ 1000 : timeGapRaw;
  final timeFactor = _timeFactor(gapMs);
  final threshold = 1.2 * unit * timeFactor;

  final aCenterY = a.bounds.center.dy;
  final bCenterY = b.bounds.center.dy;
  final verticalCenterDist = (aCenterY - bCenterY).abs();

  final horizontalGap = _horizontalGap(a.bounds, b.bounds);
  final verticalGap = _verticalGap(a.bounds, b.bounds);
  final horizontalOverlap = _horizontalOverlap(a.bounds, b.bounds);

  if (verticalCenterDist <= 0.8 * unit && horizontalGap <= threshold) {
    return true;
  }

  if (horizontalOverlap > 0 && verticalGap <= 0.45 * unit) {
    return true;
  }

  if (gapMs <= 2000 &&
      horizontalGap <= threshold &&
      verticalGap <= 0.45 * unit) {
    return true;
  }

  return false;
}

double _timeFactor(int gapMs) {
  const maxGap = 8000.0;
  final t = (gapMs / maxGap).clamp(0.0, 1.0);
  return 1.5 - t * (1.5 - 0.55);
}

double _horizontalGap(Rect a, Rect b) {
  if (a.right < b.left) return b.left - a.right;
  if (b.right < a.left) return a.left - b.right;
  return 0;
}

double _verticalGap(Rect a, Rect b) {
  if (a.bottom < b.top) return b.top - a.bottom;
  if (b.bottom < a.top) return a.top - b.bottom;
  return 0;
}

double _horizontalOverlap(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final right = math.min(a.right, b.right);
  return math.max(0, right - left);
}

Rect _unionBounds(Iterable<Rect> rects) {
  final list = rects.toList();
  var left = list.first.left;
  var top = list.first.top;
  var right = list.first.right;
  var bottom = list.first.bottom;

  for (final rect in list.skip(1)) {
    if (rect.left < left) left = rect.left;
    if (rect.top < top) top = rect.top;
    if (rect.right > right) right = rect.right;
    if (rect.bottom > bottom) bottom = rect.bottom;
  }

  return Rect.fromLTRB(left, top, right, bottom);
}
