import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/domain/models/stroke.dart';
import 'package:scrapyard/features/canvas/domain/services/stroke_cluster_detector.dart';

Stroke _stroke({
  required String id,
  required Rect bounds,
  required int startUs,
  int durationUs = 80000,
}) {
  return Stroke(
    id: id,
    color: Colors.black,
    baseWidth: 2,
    points: [
      StrokePoint(
        x: bounds.left,
        y: bounds.top,
        pressure: 0.5,
        timestamp: startUs,
      ),
      StrokePoint(
        x: bounds.right,
        y: bounds.bottom,
        pressure: 0.5,
        timestamp: startUs + durationUs,
      ),
    ],
  );
}

void main() {
  test('spaced expression with superscript merges into one cluster', () {
    // Mimics "2x^2  + 3x + 4 = 5" written quickly with a horizontal gap
    // after the squared term (microsecond timestamps).
    var t = 1000000000; // arbitrary us baseline
    const gap = 200000; // 200ms between strokes

    final strokes = <Stroke>[
      _stroke(id: '2', bounds: const Rect.fromLTWH(10, 40, 18, 28), startUs: t),
      _stroke(
          id: 'x',
          bounds: const Rect.fromLTWH(30, 42, 22, 26),
          startUs: t += gap),
      // superscript 2 — small and above the baseline
      _stroke(
          id: 'exp',
          bounds: const Rect.fromLTWH(52, 20, 12, 14),
          startUs: t += gap),
      // gap after squared term
      _stroke(
          id: 'plus1',
          bounds: const Rect.fromLTWH(100, 44, 16, 18),
          startUs: t += gap),
      _stroke(
          id: '3',
          bounds: const Rect.fromLTWH(120, 40, 16, 28),
          startUs: t += gap),
      _stroke(
          id: 'x2',
          bounds: const Rect.fromLTWH(138, 42, 20, 26),
          startUs: t += gap),
      _stroke(
          id: 'plus2',
          bounds: const Rect.fromLTWH(164, 44, 16, 18),
          startUs: t += gap),
      _stroke(
          id: '4',
          bounds: const Rect.fromLTWH(184, 40, 16, 28),
          startUs: t += gap),
      _stroke(
          id: 'eq',
          bounds: const Rect.fromLTWH(210, 48, 18, 12),
          startUs: t += gap),
      _stroke(
          id: '5',
          bounds: const Rect.fromLTWH(234, 40, 16, 28),
          startUs: t += gap),
    ];

    final clusters = detectClusters(strokes);
    expect(clusters.length, 1,
        reason: 'entire expression should be one cluster, got '
            '${clusters.map((c) => c.strokeIds).toList()}');
    expect(clusters.first.strokeIds, strokes.map((s) => s.id).toSet());
  });

  test('fast new line does not glue two expressions', () {
    var t = 1000000000;
    const gap = 150000;

    final strokes = <Stroke>[
      _stroke(id: 'a1', bounds: const Rect.fromLTWH(20, 20, 30, 24), startUs: t),
      _stroke(
          id: 'a2',
          bounds: const Rect.fromLTWH(55, 22, 28, 22),
          startUs: t += gap),
      // New line: clearly left and below
      _stroke(
          id: 'b1',
          bounds: const Rect.fromLTWH(20, 80, 30, 24),
          startUs: t += gap),
      _stroke(
          id: 'b2',
          bounds: const Rect.fromLTWH(55, 82, 28, 22),
          startUs: t += gap),
    ];

    final clusters = detectClusters(strokes);
    expect(clusters.length, 2,
        reason: 'two lines should stay separate, got '
            '${clusters.map((c) => c.strokeIds).toList()}');
  });

  test('legacy millisecond timestamps still cluster', () {
    var t = 1700000000000; // ms-scale epoch-like
    const gap = 200;

    final strokes = <Stroke>[
      _stroke(
          id: '1',
          bounds: const Rect.fromLTWH(10, 10, 20, 24),
          startUs: t,
          durationUs: 80),
      _stroke(
          id: '2',
          bounds: const Rect.fromLTWH(35, 12, 20, 22),
          startUs: t += gap,
          durationUs: 80),
      _stroke(
          id: '3',
          bounds: const Rect.fromLTWH(60, 10, 20, 24),
          startUs: t += gap,
          durationUs: 80),
    ];

    final clusters = detectClusters(strokes);
    expect(clusters.length, 1);
  });
}
