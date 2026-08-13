import 'dart:math';

import '../domain/models/stroke.dart';

/// Screen-space gap (px) above which we insert interpolated samples.
const double kStrokeGapScreenPx = 6.0;

/// World-space max gap for a given zoom ([scale] maps world → screen).
double strokeMaxGap(double scale) {
  final s = scale <= 0 ? 1.0 : scale;
  return kStrokeGapScreenPx / s;
}

/// Append [incoming] to [dest], filling gaps larger than [maxGap].
///
/// Flutter 3.44+ already expands each OS sample in a pointer packet into its
/// own [PointerMoveEvent], so capture is one event at a time. Fast flicks can
/// still leave long chords; those are filled here.
void appendInterpolated(
  List<StrokePoint> dest,
  Iterable<StrokePoint> incoming, {
  double maxGap = kStrokeGapScreenPx,
}) {
  for (final p in incoming) {
    if (dest.isEmpty) {
      dest.add(p);
      continue;
    }
    final last = dest.last;
    final dx = p.x - last.x;
    final dy = p.y - last.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 0.15) {
      dest[dest.length - 1] = p;
      continue;
    }
    dest.addAll(interpolateGap(last, p, maxGap: maxGap));
  }
}

/// Linear samples from [last] to [next] when the chord is longer than [maxGap].
List<StrokePoint> interpolateGap(
  StrokePoint? last,
  StrokePoint next, {
  double maxGap = kStrokeGapScreenPx,
}) {
  if (last == null) return [next];
  final dx = next.x - last.x;
  final dy = next.y - last.y;
  final dist = sqrt(dx * dx + dy * dy);
  if (dist <= maxGap) return [next];
  final steps = (dist / maxGap).ceil();
  final out = <StrokePoint>[];
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    out.add(StrokePoint(
      x: last.x + dx * t,
      y: last.y + dy * t,
      pressure: last.pressure + (next.pressure - last.pressure) * t,
      timestamp:
          last.timestamp + ((next.timestamp - last.timestamp) * t).round(),
    ));
  }
  return out;
}

/// Catmull-Rom resample of a centerline for rounder curves at paint time.
List<StrokePoint> catmullRomResample(
  List<StrokePoint> pts, {
  double spacing = 4.0,
}) {
  if (pts.length < 3) return pts;
  final out = <StrokePoint>[pts.first];
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1];
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist < 0.5) {
      out.add(p2);
      continue;
    }
    final steps = max(1, (dist / spacing).ceil());
    for (var s = 1; s <= steps; s++) {
      final t = s / steps;
      if (s == steps) {
        out.add(p2);
      } else {
        out.add(_catmullPoint(p0, p1, p2, p3, t));
      }
    }
  }
  return out;
}

StrokePoint _catmullPoint(
  StrokePoint p0,
  StrokePoint p1,
  StrokePoint p2,
  StrokePoint p3,
  double t,
) {
  final t2 = t * t;
  final t3 = t2 * t;
  double axis(
    double a,
    double b,
    double c,
    double d,
  ) =>
      0.5 *
      ((2 * b) +
          (-a + c) * t +
          (2 * a - 5 * b + 4 * c - d) * t2 +
          (-a + 3 * b - 3 * c + d) * t3);

  return StrokePoint(
    x: axis(p0.x, p1.x, p2.x, p3.x),
    y: axis(p0.y, p1.y, p2.y, p3.y),
    pressure: p1.pressure + (p2.pressure - p1.pressure) * t,
    timestamp: p1.timestamp + ((p2.timestamp - p1.timestamp) * t).round(),
  );
}
