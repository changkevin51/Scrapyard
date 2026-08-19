import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/domain/models/stroke.dart';
import 'package:scrapyard/features/canvas/domain/services/equals_detector.dart';

Stroke _bar({
  required String id,
  required double left,
  required double y,
  required double width,
  required int t,
}) {
  return Stroke(
    id: id,
    color: Colors.black,
    baseWidth: 2,
    points: [
      StrokePoint(x: left, y: y, pressure: 0.5, timestamp: t),
      StrokePoint(x: left + width, y: y, pressure: 0.5, timestamp: t + 40000),
    ],
  );
}

Stroke _glyph({
  required String id,
  required Rect bounds,
  required int t,
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
        timestamp: t,
      ),
      StrokePoint(
        x: bounds.right,
        y: bounds.bottom,
        pressure: 0.5,
        timestamp: t + 80000,
      ),
    ],
  );
}

void main() {
  test('detects two stacked bars after a simple expression', () {
    var t = 1000000000;
    const gap = 200000;
    final strokes = [
      _glyph(id: '2', bounds: const Rect.fromLTWH(10, 28, 16, 26), t: t),
      _glyph(
        id: 'plus',
        bounds: const Rect.fromLTWH(32, 32, 14, 18),
        t: t += gap,
      ),
      _glyph(
        id: '3',
        bounds: const Rect.fromLTWH(52, 28, 16, 26),
        t: t += gap,
      ),
      _bar(id: 'eq1', left: 80, y: 36, width: 22, t: t += gap),
      _bar(id: 'eq2', left: 80, y: 46, width: 22, t: t += gap),
    ];

    final found = detectEquals(strokes, involvingStrokeId: 'eq2');
    expect(found, isNotNull);
    expect(found!.equalsStrokeIds, {'eq1', 'eq2'});
    expect(found.expressionStrokeIds, {'2', 'plus', '3'});
  });

  test('a single minus is not equals', () {
    var t = 1000000000;
    final strokes = [
      _glyph(id: '2', bounds: const Rect.fromLTWH(10, 28, 16, 26), t: t),
      _bar(id: 'minus', left: 32, y: 40, width: 18, t: t + 200000),
      _glyph(
        id: '3',
        bounds: const Rect.fromLTWH(56, 28, 16, 26),
        t: t + 400000,
      ),
    ];
    expect(detectEquals(strokes, involvingStrokeId: 'minus'), isNull);
  });

  test('underline under a number is not equals', () {
    var t = 1000000000;
    final strokes = [
      _glyph(id: 'n', bounds: const Rect.fromLTWH(10, 20, 40, 28), t: t),
      _bar(id: 'ul', left: 8, y: 54, width: 50, t: t + 200000),
    ];
    expect(detectEquals(strokes, involvingStrokeId: 'ul'), isNull);
  });

  test('skips when the user already wrote ink to the right of equals', () {
    var t = 1000000000;
    const gap = 200000;
    final strokes = [
      _glyph(id: '2', bounds: const Rect.fromLTWH(10, 28, 16, 26), t: t),
      _glyph(
        id: 'plus',
        bounds: const Rect.fromLTWH(32, 32, 14, 18),
        t: t += gap,
      ),
      _glyph(
        id: '3',
        bounds: const Rect.fromLTWH(52, 28, 16, 26),
        t: t += gap,
      ),
      _bar(id: 'eq1', left: 80, y: 36, width: 22, t: t += gap),
      _bar(id: 'eq2', left: 80, y: 46, width: 22, t: t += gap),
      _glyph(
        id: 'ans',
        bounds: const Rect.fromLTWH(112, 28, 16, 26),
        t: t += gap,
      ),
    ];
    expect(detectEquals(strokes, involvingStrokeId: 'eq2'), isNull);
  });

  test('fraction bar with numerator and denominator is not equals', () {
    var t = 1000000000;
    final strokes = [
      _glyph(id: 'num', bounds: const Rect.fromLTWH(20, 8, 14, 18), t: t),
      _bar(id: 'frac', left: 16, y: 32, width: 28, t: t + 200000),
      _glyph(
        id: 'den',
        bounds: const Rect.fromLTWH(22, 40, 14, 18),
        t: t + 400000,
      ),
    ];
    expect(detectEquals(strokes, involvingStrokeId: 'frac'), isNull);
  });

  test('includes fraction numerator and denominator left of equals', () {
    var t = 1000000000;
    const gap = 200000;
    final strokes = [
      _glyph(id: 'num', bounds: const Rect.fromLTWH(12, 4, 16, 18), t: t),
      _bar(id: 'frac', left: 8, y: 28, width: 28, t: t += gap),
      _glyph(
        id: 'den',
        bounds: const Rect.fromLTWH(14, 36, 16, 18),
        t: t += gap,
      ),
      _bar(id: 'eq1', left: 48, y: 24, width: 20, t: t += gap),
      _bar(id: 'eq2', left: 48, y: 34, width: 20, t: t += gap),
    ];

    final found = detectEquals(strokes, involvingStrokeId: 'eq2');
    expect(found, isNotNull);
    expect(found!.expressionStrokeIds, {'num', 'frac', 'den'});
  });

  test('does not swallow a second equation on the same line', () {
    var t = 1000000000;
    const gap = 200000;
    final strokes = [
      _glyph(id: 'c', bounds: const Rect.fromLTWH(10, 28, 16, 26), t: t),
      _glyph(
        id: 'times1',
        bounds: const Rect.fromLTWH(32, 32, 14, 18),
        t: t += gap,
      ),
      _glyph(
        id: 'd',
        bounds: const Rect.fromLTWH(52, 28, 16, 26),
        t: t += gap,
      ),
      _bar(id: 'eqA1', left: 80, y: 36, width: 22, t: t += gap),
      _bar(id: 'eqA2', left: 80, y: 46, width: 22, t: t += gap),
      _glyph(
        id: 'a',
        bounds: const Rect.fromLTWH(160, 28, 16, 26),
        t: t += gap,
      ),
      _glyph(
        id: 'times2',
        bounds: const Rect.fromLTWH(182, 32, 14, 18),
        t: t += gap,
      ),
      _glyph(
        id: 'b',
        bounds: const Rect.fromLTWH(202, 28, 16, 26),
        t: t += gap,
      ),
      _bar(id: 'eqB1', left: 230, y: 36, width: 22, t: t += gap),
      _bar(id: 'eqB2', left: 230, y: 46, width: 22, t: t += gap),
    ];

    final found = detectEquals(strokes, involvingStrokeId: 'eqB2');
    expect(found, isNotNull);
    expect(found!.expressionStrokeIds, {'a', 'times2', 'b'});
  });
}
