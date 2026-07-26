import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/koto_theme.dart';
import '../../../canvas/data/pen_engine.dart';
import '../../../canvas/domain/models/canvas_smart_models.dart';
import '../../../canvas/domain/models/stroke.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';

/// Mini content preview of a scrap's handwriting strokes.
class ScrapThumbnail extends ConsumerWidget {
  final String noteId;

  const ScrapThumbnail({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strokesAsync = ref.watch(noteStrokesPreviewProvider(noteId));

    return ColoredBox(
      color: KotoTheme.background,
      child: strokesAsync.when(
        loading: () => const SizedBox.expand(),
        error: (_, __) => const SizedBox.expand(),
        data: (strokes) {
          final visible = strokes.where((s) => !s.isHidden).toList();
          if (visible.isEmpty) return const SizedBox.expand();
          return CustomPaint(
            painter: _ScrapThumbnailPainter(strokes: visible),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ScrapThumbnailPainter extends CustomPainter {
  final List<Stroke> strokes;

  _ScrapThumbnailPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _contentBounds(strokes);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;

    const pad = 24.0;
    final content = bounds.inflate(pad);
    final scale = min(
      size.width / content.width,
      size.height / content.height,
    ).clamp(0.02, 1.0);

    final dx = (size.width - content.width * scale) / 2;
    final dy = (size.height - content.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.translate(-content.left, -content.top);

    for (final stroke in strokes) {
      if (stroke.shapeType != ShapeType.none &&
          stroke.shapeVertices.isNotEmpty) {
        _paintShape(canvas, stroke);
      } else if (stroke.points.isNotEmpty) {
        StrokeRenderer.paintStyled(
          canvas: canvas,
          pts: stroke.points,
          color: stroke.color,
          baseWidth: stroke.baseWidth,
          style: stroke.penStyle,
          isHighlighter: stroke.isHighlighter,
        );
      }
    }

    canvas.restore();
  }

  Rect? _contentBounds(List<Stroke> strokes) {
    double? minX, minY, maxX, maxY;

    void include(double x, double y) {
      minX = minX == null ? x : min(minX!, x);
      minY = minY == null ? y : min(minY!, y);
      maxX = maxX == null ? x : max(maxX!, x);
      maxY = maxY == null ? y : max(maxY!, y);
    }

    for (final stroke in strokes) {
      if (stroke.shapeType != ShapeType.none &&
          stroke.shapeVertices.isNotEmpty) {
        final v = stroke.shapeVertices;
        for (int i = 0; i + 1 < v.length; i += 2) {
          include(v[i], v[i + 1]);
        }
      } else {
        for (final p in stroke.points) {
          include(p.x, p.y);
        }
      }
    }

    if (minX == null) return null;
    // Ensure a non-zero box for single-point strokes.
    if (maxX! - minX! < 1) maxX = minX! + 1;
    if (maxY! - minY! < 1) maxY = minY! + 1;
    return Rect.fromLTRB(minX!, minY!, maxX!, maxY!);
  }

  void _paintShape(Canvas canvas, Stroke stroke) {
    final v = stroke.shapeVertices;
    final p = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.baseWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (stroke.shapeType) {
      case ShapeType.line:
        if (v.length >= 4) {
          canvas.drawLine(Offset(v[0], v[1]), Offset(v[2], v[3]), p);
        }
      case ShapeType.circle:
      case ShapeType.oval:
        if (v.length >= 4) {
          canvas.drawOval(Rect.fromLTRB(v[0], v[1], v[2], v[3]), p);
        }
      case ShapeType.rectangle:
      case ShapeType.square:
        if (v.length >= 4) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(v[0], v[1], v[2], v[3]),
              const Radius.circular(4),
            ),
            p,
          );
        }
      case ShapeType.triangle:
        if (v.length >= 6) {
          canvas.drawPath(
            Path()
              ..moveTo(v[0], v[1])
              ..lineTo(v[2], v[3])
              ..lineTo(v[4], v[5])
              ..close(),
            p,
          );
        }
      case ShapeType.diamond:
        if (v.length >= 8) {
          canvas.drawPath(
            Path()
              ..moveTo(v[0], v[1])
              ..lineTo(v[2], v[3])
              ..lineTo(v[4], v[5])
              ..lineTo(v[6], v[7])
              ..close(),
            p,
          );
        }
      case ShapeType.star:
        if (v.length >= 10) {
          final path = Path()..moveTo(v[0], v[1]);
          for (int i = 2; i < v.length; i += 2) {
            path.lineTo(v[i], v[i + 1]);
          }
          path.close();
          canvas.drawPath(path, p);
        }
      case ShapeType.none:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ScrapThumbnailPainter old) =>
      !identical(old.strokes, strokes);
}
