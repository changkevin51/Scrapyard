import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/data/smart_shape_recognizer.dart';
import 'package:scrapyard/features/canvas/domain/models/canvas_smart_models.dart';
import 'package:scrapyard/features/canvas/domain/models/stroke.dart';

List<StrokePoint> _pts(List<(double, double)> xy) {
  return [
    for (int i = 0; i < xy.length; i++)
      StrokePoint(x: xy[i].$1, y: xy[i].$2, pressure: 0.5, timestamp: i * 8),
  ];
}

List<StrokePoint> _circle({double cx = 200, double cy = 200, double r = 80}) {
  return _pts([
    for (int i = 0; i <= 72; i++)
      (
        cx + r * math.cos(2 * math.pi * i / 72),
        cy + r * math.sin(2 * math.pi * i / 72),
      ),
  ]);
}

List<StrokePoint> _square({double x = 120, double y = 120, double s = 160}) {
  const n = 20;
  final xy = <(double, double)>[];
  for (int i = 0; i <= n; i++) {
    xy.add((x + s * i / n, y));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x + s, y + s * i / n));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x + s * (1 - i / n), y + s));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x, y + s * (1 - i / n)));
  }
  return _pts(xy);
}

List<StrokePoint> _rectangle({
  double x = 80,
  double y = 140,
  double w = 220,
  double h = 100,
}) {
  const n = 24;
  final xy = <(double, double)>[];
  for (int i = 0; i <= n; i++) {
    xy.add((x + w * i / n, y));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x + w, y + h * i / n));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x + w * (1 - i / n), y + h));
  }
  for (int i = 1; i <= n; i++) {
    xy.add((x, y + h * (1 - i / n)));
  }
  return _pts(xy);
}

List<StrokePoint> _oval({
  double cx = 200,
  double cy = 200,
  double rx = 120,
  double ry = 55,
}) {
  return _pts([
    for (int i = 0; i <= 72; i++)
      (
        cx + rx * math.cos(2 * math.pi * i / 72),
        cy + ry * math.sin(2 * math.pi * i / 72),
      ),
  ]);
}

List<StrokePoint> _wobblyCircle() {
  final rnd = math.Random(4);
  return _pts([
    for (int i = 0; i <= 72; i++)
      (
        200 + (80 + rnd.nextDouble() * 6 - 3) * math.cos(2 * math.pi * i / 72),
        200 + (80 + rnd.nextDouble() * 6 - 3) * math.sin(2 * math.pi * i / 72),
      ),
  ]);
}

List<StrokePoint> _line() {
  return _pts([
    for (int i = 0; i <= 40; i++) (80.0 + i * 6, 300.0 + i * 0.4),
  ]);
}

List<StrokePoint> _diamond() {
  const cx = 200.0, cy = 200.0, r = 90.0;
  const n = 16;
  final corners = [
    (cx, cy - r),
    (cx + r, cy),
    (cx, cy + r),
    (cx - r, cy),
    (cx, cy - r),
  ];
  final xy = <(double, double)>[];
  for (int s = 0; s < 4; s++) {
    final a = corners[s];
    final b = corners[s + 1];
    final start = s == 0 ? 0 : 1;
    for (int i = start; i <= n; i++) {
      final t = i / n;
      xy.add((a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t));
    }
  }
  return _pts(xy);
}

List<StrokePoint> _triangle() {
  const n = 18;
  final corners = [(200.0, 80.0), (80.0, 280.0), (320.0, 280.0), (200.0, 80.0)];
  final xy = <(double, double)>[];
  for (int s = 0; s < 3; s++) {
    final a = corners[s];
    final b = corners[s + 1];
    final start = s == 0 ? 0 : 1;
    for (int i = start; i <= n; i++) {
      final t = i / n;
      xy.add((a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t));
    }
  }
  return _pts(xy);
}

void main() {
  final recognizer = SmartShapeRecognizer();

  test('circles are not classified as squares', () {
    final r = recognizer.recognize(_circle(), fromShapeTool: true);
    expect(r.type, ShapeType.circle);
  });

  test('squares are not classified as circles', () {
    final r = recognizer.recognize(_square(), fromShapeTool: true);
    expect(r.type, ShapeType.square);
  });

  test('straight strokes become lines', () {
    final r = recognizer.recognize(_line(), fromShapeTool: true);
    expect(r.type, ShapeType.line);
  });

  test('rectangles stay rectangles', () {
    final r = recognizer.recognize(_rectangle(), fromShapeTool: true);
    expect(r.type, ShapeType.rectangle);
  });

  test('ovals stay ovals', () {
    final r = recognizer.recognize(_oval(), fromShapeTool: true);
    expect(r.type, ShapeType.oval);
  });

  test('slightly wobbly circles stay circles', () {
    final r = recognizer.recognize(_wobblyCircle(), fromShapeTool: true);
    expect(r.type, ShapeType.circle);
  });

  test('diamonds are not classified as squares', () {
    final r = recognizer.recognize(_diamond(), fromShapeTool: true);
    expect(r.type, ShapeType.diamond);
  });

  test('triangles stay triangles', () {
    final r = recognizer.recognize(_triangle(), fromShapeTool: true);
    expect(r.type, ShapeType.triangle);
  });
}
