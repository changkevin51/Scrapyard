import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/stroke_cluster_detector.dart';
import 'canvas_providers.dart';

export '../../domain/services/stroke_cluster_detector.dart' show StrokeCluster;

/// Background-detected expression clusters. Never painted unless the Smelt
/// tool explicitly reveals a hit — so this cannot interfere with drawing or lasso.
final detectedClustersProvider =
    StateNotifierProvider<StrokeClusterNotifier, List<StrokeCluster>>((ref) {
  return StrokeClusterNotifier(ref);
});

class StrokeClusterNotifier extends StateNotifier<List<StrokeCluster>> {
  final Ref _ref;
  Timer? _debounce;
  ProviderSubscription? _strokesSub;

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

  void _runDetect() {
    final strokes = _ref.read(strokesProvider);
    state = detectClusters(strokes);
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
