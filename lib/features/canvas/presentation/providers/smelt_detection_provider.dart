import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/stroke.dart';
import '../../domain/services/stroke_cluster_detector.dart';
import 'canvas_providers.dart';

export '../../domain/services/stroke_cluster_detector.dart' show StrokeCluster;

/// Background-detected expression clusters. Never painted unless the Smelt
/// tool explicitly reveals a hit — so this cannot interfere with drawing or lasso.
final detectedClustersProvider =
    StateNotifierProvider<StrokeClusterNotifier, List<StrokeCluster>>((ref) {
  return StrokeClusterNotifier(ref);
});

/// Session-scoped user-corrected Smelt boxes (stroke ids only).
/// Bounds are recomputed from [strokesProvider] at hit-test time.
final manualClustersProvider =
    StateNotifierProvider<ManualClusterNotifier, List<ManualClusterEntry>>(
        (ref) {
  return ManualClusterNotifier(ref);
});

class ManualClusterEntry {
  final String noteId;
  final Set<String> strokeIds;

  const ManualClusterEntry({
    required this.noteId,
    required this.strokeIds,
  });
}

class ManualClusterNotifier extends StateNotifier<List<ManualClusterEntry>> {
  final Ref _ref;

  ManualClusterNotifier(this._ref) : super(const []);

  /// Register a user-corrected selection. Replaces any entry that overlaps
  /// the same strokes for this note.
  void remember({
    required String noteId,
    required Set<String> strokeIds,
  }) {
    if (strokeIds.isEmpty) return;
    final next = state
        .where((e) =>
            e.noteId != noteId || e.strokeIds.intersection(strokeIds).isEmpty)
        .toList();
    next.add(ManualClusterEntry(noteId: noteId, strokeIds: Set.of(strokeIds)));
    state = next;
  }

  /// Hit-test manual boxes for [noteId], recomputing bounds from live strokes.
  /// Prefer the smallest containing box, else nearest within [snapRadius].
  StrokeCluster? hitTest(
    Offset p, {
    required String noteId,
    double snapRadius = 24,
  }) {
    final strokes = _ref.read(strokesProvider);
    final liveIds = {
      for (final s in strokes)
        if (!s.isHidden && s.points.isNotEmpty) s.id,
    };

    // Prune deleted/hidden strokes from entries (and drop empty ones).
    var changed = false;
    final pruned = <ManualClusterEntry>[];
    for (final e in state) {
      if (e.noteId != noteId) {
        pruned.add(e);
        continue;
      }
      final kept = e.strokeIds.intersection(liveIds);
      if (kept.isEmpty) {
        changed = true;
        continue;
      }
      if (kept.length != e.strokeIds.length) {
        changed = true;
        pruned.add(ManualClusterEntry(noteId: e.noteId, strokeIds: kept));
      } else {
        pruned.add(e);
      }
    }
    if (changed) state = pruned;

    StrokeCluster? containing;
    double containingArea = double.infinity;
    StrokeCluster? nearest;
    double nearestDist = double.infinity;

    for (final e in state) {
      if (e.noteId != noteId) continue;
      final bounds = _boundsForStrokeIds(strokes, e.strokeIds);
      if (bounds == null) continue;

      final sortedIds = e.strokeIds.toList()..sort();
      final cluster = StrokeCluster(
        id: 'manual:${sortedIds.join('|').hashCode.toRadixString(16)}',
        bounds: bounds.inflate(8),
        strokeIds: Set.of(e.strokeIds),
      );

      if (cluster.bounds.contains(p)) {
        final area = cluster.bounds.width * cluster.bounds.height;
        if (area < containingArea) {
          containingArea = area;
          containing = cluster;
        }
      } else {
        final inflated = cluster.bounds.inflate(snapRadius);
        if (inflated.contains(p)) {
          final dist = _distanceToRect(p, cluster.bounds);
          if (dist < nearestDist) {
            nearestDist = dist;
            nearest = cluster;
          }
        }
      }
    }

    return containing ?? nearest;
  }

  static Rect? _boundsForStrokeIds(List<Stroke> strokes, Set<String> ids) {
    Rect? union;
    for (final stroke in strokes) {
      if (!ids.contains(stroke.id) || stroke.isHidden || stroke.points.isEmpty) {
        continue;
      }
      final b = _strokeBounds(stroke);
      union = union == null
          ? b
          : Rect.fromLTRB(
              math.min(union.left, b.left),
              math.min(union.top, b.top),
              math.max(union.right, b.right),
              math.max(union.bottom, b.bottom),
            );
    }
    return union;
  }

  static Rect _strokeBounds(Stroke stroke) {
    double minX = stroke.points.first.x;
    double maxX = stroke.points.first.x;
    double minY = stroke.points.first.y;
    double maxY = stroke.points.first.y;
    for (final p in stroke.points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static double _distanceToRect(Offset p, Rect r) {
    final dx = p.dx < r.left
        ? r.left - p.dx
        : (p.dx > r.right ? p.dx - r.right : 0.0);
    final dy = p.dy < r.top
        ? r.top - p.dy
        : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
    return dx * dx + dy * dy;
  }
}

class StrokeClusterNotifier extends StateNotifier<List<StrokeCluster>> {
  final Ref _ref;
  Timer? _debounce;
  ProviderSubscription? _strokesSub;
  int _runId = 0;

  StrokeClusterNotifier(this._ref) : super(const []) {
    _strokesSub = _ref.listen(strokesProvider, (previous, next) {
      _scheduleDetect();
    });
    // Run once for already-loaded strokes.
    _scheduleDetect();
  }

  void _scheduleDetect() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _runDetect);
  }

  Future<void> _runDetect() async {
    final strokes = _ref.read(strokesProvider);
    final runId = ++_runId;

    // Build a tiny serializable DTO so the isolate never touches Flutter objects.
    final payload = <Map<String, dynamic>>[];
    for (final stroke in strokes) {
      if (stroke.isHidden || stroke.points.isEmpty) continue;
      double minX = stroke.points.first.x;
      double maxX = stroke.points.first.x;
      double minY = stroke.points.first.y;
      double maxY = stroke.points.first.y;
      for (final p in stroke.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      payload.add({
        'id': stroke.id,
        'left': minX,
        'top': minY,
        'right': maxX,
        'bottom': maxY,
        'startTime': stroke.points.first.timestamp,
        'endTime': stroke.points.last.timestamp,
      });
    }

    final clusters = await detectClustersIsolate(payload);
    // Drop stale results if a newer run was scheduled.
    if (runId != _runId) return;
    state = clusters;
  }

  /// Prefer the smallest cluster containing [p], else the nearest cluster
  /// within [snapRadius], else null.
  StrokeCluster? hitTest(Offset p, {double snapRadius = 24}) {
    StrokeCluster? containing;
    double containingArea = double.infinity;

    StrokeCluster? nearest;
    double nearestDist = double.infinity;

    for (final cluster in state) {
      if (cluster.bounds.contains(p)) {
        final area = cluster.bounds.width * cluster.bounds.height;
        if (area < containingArea) {
          containingArea = area;
          containing = cluster;
        }
      } else {
        final inflated = cluster.bounds.inflate(snapRadius);
        if (inflated.contains(p)) {
          final dist = _distanceToRect(p, cluster.bounds);
          if (dist < nearestDist) {
            nearestDist = dist;
            nearest = cluster;
          }
        }
      }
    }

    return containing ?? nearest;
  }

  static double _distanceToRect(Offset p, Rect r) {
    final dx = p.dx < r.left
        ? r.left - p.dx
        : (p.dx > r.right ? p.dx - r.right : 0.0);
    final dy = p.dy < r.top
        ? r.top - p.dy
        : (p.dy > r.bottom ? p.dy - r.bottom : 0.0);
    return dx * dx + dy * dy;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _strokesSub?.close();
    super.dispose();
  }
}
