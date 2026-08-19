import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/domain/models/stroke.dart';
import 'package:scrapyard/features/canvas/domain/services/math_ink_normalizer.dart';

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
      StrokePoint(x: bounds.left, y: bounds.top, pressure: 0.5, timestamp: t),
      StrokePoint(
        x: bounds.right,
        y: bounds.bottom,
        pressure: 0.5,
        timestamp: t + 40000,
      ),
    ],
  );
}

void main() {
  test('x between digits becomes multiply', () {
    expect(
      normalizeMathInk(recognized: '2x3', expressionStrokes: const []),
      '2*3',
    );
    expect(
      normalizeMathInk(recognized: '2X(1+1)', expressionStrokes: const []),
      '2*(1+1)',
    );
  });

  test('leftover letters abort', () {
    expect(
      normalizeMathInk(recognized: 'x+2', expressionStrokes: const []),
      isNull,
    );
    expect(
      normalizeMathInk(recognized: '2y3', expressionStrokes: const []),
      isNull,
    );
    expect(
      normalizeMathInk(recognized: 'sqrt2', expressionStrokes: const []),
      isNull,
    );
  });

  test('inserts caret when glyph count matches superscripts', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(10, 30, 16, 24), t: 1),
      _glyph(id: '2', bounds: const Rect.fromLTWH(28, 12, 10, 12), t: 2),
    ];
    expect(
      normalizeMathInk(recognized: '32', expressionStrokes: strokes),
      '3^2',
    );
  });

  test('aborts when superscripts cannot be aligned', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(10, 30, 16, 24), t: 1),
      _glyph(id: 'plus', bounds: const Rect.fromLTWH(30, 34, 12, 14), t: 2),
      _glyph(id: '2', bounds: const Rect.fromLTWH(48, 12, 10, 12), t: 3),
    ];
    // Three glyphs, two recognized chars — cannot zip confidently.
    expect(
      normalizeMathInk(recognized: '32', expressionStrokes: strokes),
      isNull,
    );
  });

  test('stacked fraction aborts', () {
    final strokes = [
      _glyph(id: 'num', bounds: const Rect.fromLTWH(20, 4, 14, 16), t: 1),
      Stroke(
        id: 'bar',
        color: Colors.black,
        baseWidth: 2,
        points: const [
          StrokePoint(x: 16, y: 28, pressure: 0.5, timestamp: 2),
          StrokePoint(x: 44, y: 28, pressure: 0.5, timestamp: 3),
        ],
      ),
      _glyph(id: 'den', bounds: const Rect.fromLTWH(22, 36, 14, 16), t: 4),
    ];
    expect(
      normalizeMathInk(recognized: '12', expressionStrokes: strokes),
      isNull,
    );
  });

  test('midline minus is not treated as an exponent', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(10, 20, 18, 30), t: 1),
      Stroke(
        id: 'minus',
        color: Colors.black,
        baseWidth: 2,
        points: const [
          StrokePoint(x: 36, y: 34, pressure: 0.5, timestamp: 2),
          StrokePoint(x: 58, y: 35, pressure: 0.5, timestamp: 3),
        ],
      ),
      _glyph(id: '2', bounds: const Rect.fromLTWH(66, 22, 16, 26), t: 4),
    ];
    expect(
      normalizeMathInk(recognized: '30-2', expressionStrokes: strokes),
      '30-2',
    );
    expect(
      firstSolvableCandidate(
        candidates: ['30-2', '30-Z'],
        expressionStrokes: strokes,
      )!.display,
      '28',
    );
  });

  test('geometric plus rewrites ML Kit minus', () {
    final strokes = [
      _glyph(id: 'a', bounds: const Rect.fromLTWH(8, 18, 16, 28), t: 1),
      Stroke(
        id: 'plusH',
        color: Colors.black,
        baseWidth: 2,
        points: const [
          StrokePoint(x: 30, y: 32, pressure: 0.5, timestamp: 2),
          StrokePoint(x: 56, y: 33, pressure: 0.5, timestamp: 3),
        ],
      ),
      Stroke(
        id: 'plusV',
        color: Colors.black,
        baseWidth: 2,
        points: const [
          StrokePoint(x: 42, y: 18, pressure: 0.5, timestamp: 4),
          StrokePoint(x: 43, y: 46, pressure: 0.5, timestamp: 5),
        ],
      ),
      _glyph(id: 'b', bounds: const Rect.fromLTWH(64, 20, 16, 26), t: 6),
    ];
    expect(
      normalizeMathInk(recognized: '2-2', expressionStrokes: strokes),
      '2+2',
    );
    expect(
      firstSolvableCandidate(
        candidates: ['2-2', '2-Z'],
        expressionStrokes: strokes,
      )!.display,
      '4',
    );
  });

  test('first solvable candidate wins', () {
    final result = firstSolvableCandidate(
      candidates: ['xx', '2+2', 'nope'],
      expressionStrokes: const [],
    );
    expect(result, isNotNull);
    expect(result!.display, '4');
  });
}
