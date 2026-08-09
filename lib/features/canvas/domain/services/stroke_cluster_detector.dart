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
  /// Stroke start time in milliseconds.
  final int startTime;
  /// Stroke end time in milliseconds.
  final int endTime;

  const _StrokeInfo({
    required this.id,
    required this.bounds,
    required this.startTime,
    required this.endTime,
  });
}

class _MutableCluster {
  List<_StrokeInfo> members;
  Rect bounds;
  int minStart;
  int maxEnd;

  _MutableCluster(this.members)
      : bounds = _unionBounds(members.map((m) => m.bounds)),
        minStart = members.map((m) => m.startTime).reduce(math.min),
        maxEnd = members.map((m) => m.endTime).reduce(math.max);

  void absorb(_MutableCluster other) {
    members = [...members, ...other.members];
    bounds = _unionBounds([bounds, other.bounds]);
    minStart = math.min(minStart, other.minStart);
    maxEnd = math.max(maxEnd, other.maxEnd);
  }
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
/// `id`, `left`, `top`, `right`, `bottom`, `startTime`, `endTime`.
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
          startTime: (m['startTime'] as num?)?.toInt() ??
              (m['endTime'] as num).toInt(),
          endTime: (m['endTime'] as num).toInt(),
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
      startTime: stroke.points.first.timestamp,
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

  // Normalize raw timestamps (us or ms) to milliseconds once per run.
  infos = _normalizeTimestamps(infos);

  final unit = _estimateWritingUnit(infos);
  final uf = _UnionFind(infos.length);

  // Pass 1: pairwise spatial merge modulated by timing.
  for (var i = 0; i < infos.length; i++) {
    for (var j = i + 1; j < infos.length; j++) {
      if (_shouldMerge(infos[i], infos[j], unit)) {
        uf.union(i, j);
      }
    }
  }

  // Pass 2: temporal chaining — consecutive strokes written quickly are
  // likely the same expression even if a gap looks spatially large.
  _temporalChainPass(infos, uf, unit);

  final groups = <int, List<_StrokeInfo>>{};
  for (var i = 0; i < infos.length; i++) {
    final root = uf.find(i);
    groups.putIfAbsent(root, () => []).add(infos[i]);
  }

  var clusters = groups.values.map(_MutableCluster.new).toList();

  // Pass 3: merge nearby clusters (superscripts, spaced terms, etc.).
  clusters = _mergeClusters(clusters, unit);

  // Pass 4: attach tiny orphan strokes instead of dropping them.
  clusters = _attachOrphans(clusters, unit);

  final result = <StrokeCluster>[];
  for (final c in clusters) {
    final bounds = c.bounds.inflate(8);
    final strokeIds = c.members.map((m) => m.id).toSet();

    if (bounds.width > canvasWidth * 0.7 && c.members.length < 3) continue;

    final sortedIds = strokeIds.toList()..sort();
    result.add(StrokeCluster(
      id: sortedIds.join('|').hashCode.toRadixString(16),
      bounds: bounds,
      strokeIds: strokeIds,
    ));
  }

  return result;
}

/// Convert stroke timestamps to milliseconds.
///
/// New strokes use microseconds (`PointerEvent.timeStamp.inMicroseconds`).
/// Legacy strokes may store milliseconds. Infer once from the data.
List<_StrokeInfo> _normalizeTimestamps(List<_StrokeInfo> infos) {
  if (infos.isEmpty) return infos;

  final ends = infos.map((i) => i.endTime).toList()..sort();
  final starts = infos.map((i) => i.startTime).toList()..sort();

  // Median positive consecutive end-time delta.
  final deltas = <int>[];
  for (var i = 1; i < ends.length; i++) {
    final d = ends[i] - ends[i - 1];
    if (d > 0) deltas.add(d);
  }
  deltas.sort();
  final medianDelta = deltas.isEmpty ? 0 : deltas[deltas.length ~/ 2];
  final maxTs = math.max(ends.last, starts.last);

  // Microseconds if median inter-stroke gap looks like hundreds of thousands,
  // or absolute timestamps are far larger than typical ms epoch fragments.
  final isMicroseconds = medianDelta > 20000 || maxTs > 5000000;
  if (!isMicroseconds) return infos;

  return [
    for (final i in infos)
      _StrokeInfo(
        id: i.id,
        bounds: i.bounds,
        startTime: i.startTime ~/ 1000,
        endTime: i.endTime ~/ 1000,
      ),
  ];
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
  final gapMs = _timeGapMs(a, b);
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

/// Union time-adjacent strokes that are spatially plausible.
void _temporalChainPass(List<_StrokeInfo> infos, _UnionFind uf, double unit) {
  if (infos.length < 2) return;

  final order = List<int>.generate(infos.length, (i) => i)
    ..sort((a, b) => infos[a].startTime.compareTo(infos[b].startTime));

  for (var k = 0; k < order.length - 1; k++) {
    final i = order[k];
    final j = order[k + 1];
    final a = infos[i];
    final b = infos[j];

    final gapMs = b.startTime - a.endTime;
    if (gapMs < 0 || gapMs > 1200) continue;

    // New-line guard: next stroke starts clearly left and below previous.
    final startsLeft = b.bounds.left < a.bounds.left - 0.5 * unit;
    final startsBelow = b.bounds.top > a.bounds.bottom + 0.3 * unit;
    if (startsLeft && startsBelow) continue;

    final verticalOverlap = _verticalOverlap(a.bounds, b.bounds);
    final verticalCenterDist =
        (a.bounds.center.dy - b.bounds.center.dy).abs();
    final sameLine = verticalOverlap > 0 || verticalCenterDist <= 1.5 * unit;
    if (!sameLine) continue;

    final horizontalGap = _horizontalGap(a.bounds, b.bounds);
    if (horizontalGap > 4 * unit) continue;

    uf.union(i, j);
  }
}

List<_MutableCluster> _mergeClusters(
  List<_MutableCluster> clusters,
  double unit,
) {
  if (clusters.length < 2) return clusters;

  var changed = true;
  while (changed) {
    changed = false;
    outer:
    for (var i = 0; i < clusters.length; i++) {
      for (var j = i + 1; j < clusters.length; j++) {
        if (_shouldMergeClusters(clusters[i], clusters[j], unit)) {
          clusters[i].absorb(clusters[j]);
          clusters.removeAt(j);
          changed = true;
          break outer;
        }
      }
    }
  }
  return clusters;
}

bool _shouldMergeClusters(_MutableCluster a, _MutableCluster b, double unit) {
  final horizontalGap = _horizontalGap(a.bounds, b.bounds);
  final horizontalOverlap = _horizontalOverlap(a.bounds, b.bounds);
  if (horizontalGap > 1.5 * unit && horizontalOverlap <= 0) return false;

  final timeGap = _clusterTimeGapMs(a, b);
  if (timeGap > 2500) return false;

  final smallerH = math.min(a.bounds.height, b.bounds.height);
  final vOverlap = _verticalOverlap(a.bounds, b.bounds);
  if (smallerH > 0 && vOverlap >= 0.4 * smallerH) return true;

  // Satellite rule: small cluster (superscript / subscript / dot) near another.
  final aSmall = a.bounds.height < 0.6 * unit;
  final bSmall = b.bounds.height < 0.6 * unit;
  if (aSmall || bSmall) {
    final small = aSmall ? a : b;
    final large = aSmall ? b : a;
    final nearAbove = small.bounds.bottom >= large.bounds.top - 1.2 * unit &&
        small.bounds.top <= large.bounds.top + 0.5 * unit;
    final nearBelow = small.bounds.top <= large.bounds.bottom + 1.2 * unit &&
        small.bounds.bottom >= large.bounds.bottom - 0.5 * unit;
    final nearVertically = nearAbove ||
        nearBelow ||
        _verticalGap(small.bounds, large.bounds) <= 1.2 * unit;
    if (nearVertically) return true;
  }

  return false;
}

List<_MutableCluster> _attachOrphans(
  List<_MutableCluster> clusters,
  double unit,
) {
  if (clusters.isEmpty) return clusters;

  final orphans = <_MutableCluster>[];
  final keep = <_MutableCluster>[];

  for (final c in clusters) {
    if (c.members.length == 1) {
      final b = c.members.first.bounds;
      if (b.width < 0.5 * unit && b.height < 0.5 * unit) {
        orphans.add(c);
        continue;
      }
    }
    keep.add(c);
  }

  for (final orphan in orphans) {
    _MutableCluster? nearest;
    var nearestDist = double.infinity;
    for (final c in keep) {
      final dist = _rectDistance(orphan.bounds, c.bounds);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = c;
      }
    }
    if (nearest != null && nearestDist <= 1.5 * unit) {
      nearest.absorb(orphan);
    }
    // Else drop — nothing nearby.
  }

  return keep;
}

int _timeGapMs(_StrokeInfo a, _StrokeInfo b) {
  // Gap between stroke intervals (0 if they overlap in time).
  if (a.endTime < b.startTime) return b.startTime - a.endTime;
  if (b.endTime < a.startTime) return a.startTime - b.endTime;
  return 0;
}

int _clusterTimeGapMs(_MutableCluster a, _MutableCluster b) {
  if (a.maxEnd < b.minStart) return b.minStart - a.maxEnd;
  if (b.maxEnd < a.minStart) return a.minStart - b.maxEnd;
  return 0;
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

double _verticalOverlap(Rect a, Rect b) {
  final top = math.max(a.top, b.top);
  final bottom = math.min(a.bottom, b.bottom);
  return math.max(0, bottom - top);
}

double _rectDistance(Rect a, Rect b) {
  final dx = _horizontalGap(a, b);
  final dy = _verticalGap(a, b);
  return math.sqrt(dx * dx + dy * dy);
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
