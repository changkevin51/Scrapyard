import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/canvas/domain/models/stroke.dart';
import 'package:scrapyard/features/canvas/domain/services/ink_geometry.dart';

Stroke _hBar({
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
      StrokePoint(x: left + width, y: y + 1, pressure: 0.5, timestamp: t + 1),
    ],
  );
}

Stroke _vBar({
  required String id,
  required double x,
  required double top,
  required double height,
  required int t,
}) {
  return Stroke(
    id: id,
    color: Colors.black,
    baseWidth: 2,
    points: [
      StrokePoint(x: x, y: top, pressure: 0.5, timestamp: t),
      StrokePoint(x: x + 1, y: top + height, pressure: 0.5, timestamp: t + 1),
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
      StrokePoint(x: bounds.left, y: bounds.top, pressure: 0.5, timestamp: t),
      StrokePoint(
        x: bounds.right,
        y: bounds.bottom,
        pressure: 0.5,
        timestamp: t + 1,
      ),
    ],
  );
}

void main() {
  test('crossed bars are a plus, not a minus', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(0, 16, 18, 30), t: 1),
      _hBar(id: 'h', left: 28, y: 30, width: 26, t: 2),
      _vBar(id: 'v', x: 40, top: 16, height: 30, t: 3),
      _glyph(id: '2', bounds: const Rect.fromLTWH(62, 18, 16, 26), t: 4),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '+');
    final parts = splitOperands(strokes, ops);
    expect(parts.length, 2);
    expect(parts[0].map((s) => s.id), ['3']);
    expect(parts[1].map((s) => s.id), ['2']);
  });

  test('isolated bar between digits is minus', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(0, 16, 18, 30), t: 1),
      _hBar(id: 'h', left: 28, y: 30, width: 20, t: 2),
      _glyph(id: '2', bounds: const Rect.fromLTWH(56, 18, 16, 26), t: 3),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '-');
  });

  test('plus stem is not grouped into the neighboring digit', () {
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(0, 16, 22, 32), t: 1),
      _hBar(id: 'h', left: 30, y: 30, width: 28, t: 2),
      _vBar(id: 'v', x: 32, top: 16, height: 30, t: 3),
      _glyph(id: '2', bounds: const Rect.fromLTWH(66, 18, 16, 26), t: 4),
    ];
    final glyphs = groupGlyphs(strokes);
    expect(glyphs.length, 3);
    final ops = detectArithmeticOperators(strokes);
    expect(ops.single.symbol, '+');
  });

  test('plus still detected when the stem sits left of the bar', () {
    // Matches device logs: vertical ~9px left of the crossbar, merged into
    // the previous digit by naive x-overlap grouping.
    final strokes = [
      _glyph(id: '3', bounds: const Rect.fromLTWH(0, 16, 24, 36), t: 1),
      _vBar(id: 'v', x: 26, top: 16, height: 30, t: 2),
      _hBar(id: 'h', left: 36, y: 30, width: 30, t: 3),
      _glyph(id: '2', bounds: const Rect.fromLTWH(74, 18, 22, 28), t: 4),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '+');
    final parts = splitOperands(strokes, ops);
    expect(parts[0].map((s) => s.id), ['3']);
    expect(parts[1].map((s) => s.id), ['2']);
  });

  test('short thick plus stem still counts as plus', () {
    // Typical handwriting: vertical shorter than the bar and not 1.8:1 thin.
    final strokes = [
      _glyph(id: '2', bounds: const Rect.fromLTWH(0, 16, 16, 26), t: 1),
      _hBar(id: 'h', left: 24, y: 28, width: 22, t: 2),
      Stroke(
        id: 'v',
        color: Colors.black,
        baseWidth: 2,
        points: const [
          StrokePoint(x: 32, y: 22, pressure: 0.5, timestamp: 3),
          StrokePoint(x: 40, y: 34, pressure: 0.5, timestamp: 4),
        ],
      ),
      _glyph(id: '2', bounds: const Rect.fromLTWH(52, 16, 16, 26), t: 5),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '+');
  });

  test('chubby handwritten plus still counts', () {
    // Bar is only ~1.7× as wide as tall — fails isHorizontalBar (needs 2.2).
    final strokes = [
      _glyph(id: '2', bounds: const Rect.fromLTWH(0, 16, 16, 24), t: 1),
      Stroke(
        id: 'h',
        color: Colors.black,
        baseWidth: 3,
        points: const [
          StrokePoint(x: 24, y: 26, pressure: 0.5, timestamp: 2),
          StrokePoint(x: 40, y: 35, pressure: 0.5, timestamp: 3),
        ],
      ),
      Stroke(
        id: 'v',
        color: Colors.black,
        baseWidth: 3,
        points: const [
          StrokePoint(x: 30, y: 20, pressure: 0.5, timestamp: 4),
          StrokePoint(x: 36, y: 40, pressure: 0.5, timestamp: 5),
        ],
      ),
      _glyph(id: '2', bounds: const Rect.fromLTWH(48, 16, 16, 24), t: 6),
    ];
    expect(isHorizontalBar(strokes[1]), isFalse);
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '+');
  });

  test('a digit 1 beside a minus is not a plus', () {
    final strokes = [
      _glyph(id: '1', bounds: const Rect.fromLTWH(0, 10, 8, 32), t: 1),
      _hBar(id: 'h', left: 18, y: 26, width: 20, t: 2),
      _glyph(id: '5', bounds: const Rect.fromLTWH(46, 12, 16, 28), t: 3),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '-');
  });

  test('plus still detected when the expression is written with gaps', () {
    // 2        +        2  — stem sits beside the bar, digits are far.
    final strokes = [
      _glyph(id: 'a', bounds: const Rect.fromLTWH(0, 16, 16, 26), t: 1),
      _vBar(id: 'v', x: 72, top: 14, height: 28, t: 2),
      _hBar(id: 'h', left: 88, y: 28, width: 22, t: 3),
      _glyph(id: 'b', bounds: const Rect.fromLTWH(150, 16, 16, 26), t: 4),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '+');
    final parts = splitOperands(strokes, ops);
    expect(parts[0].map((s) => s.id), ['a']);
    expect(parts[1].map((s) => s.id), ['b']);
  });

  test('multi-stroke 5 after a minus is not a plus', () {
    // 6 - 5, where 5 is a vertical body plus a top hat.
    final strokes = [
      _glyph(id: '6', bounds: const Rect.fromLTWH(0, 12, 18, 30), t: 1),
      _hBar(id: 'minus', left: 28, y: 26, width: 20, t: 2),
      _vBar(id: 'fiveBody', x: 56, top: 12, height: 28, t: 3),
      _hBar(id: 'fiveHat', left: 56, y: 12, width: 16, t: 4),
    ];
    final ops = detectArithmeticOperators(strokes);
    expect(ops.length, 1);
    expect(ops.single.symbol, '-');
  });
}
