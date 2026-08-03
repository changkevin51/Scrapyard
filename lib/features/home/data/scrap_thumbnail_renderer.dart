import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/scrapyard_theme.dart';
import '../../canvas/data/ink_renderer.dart';
import '../../canvas/domain/models/canvas_smart_models.dart';
import '../../canvas/domain/models/stroke.dart';

/// Renders scrap strokes into a fixed-size [ui.Picture] for grid thumbnails.
/// Called once per note (then cached) — not on every scroll frame.
class ScrapThumbnailRenderer {
  static const Size thumbnailSize = Size(400, 360);

  static ui.Picture render(List<Stroke> strokes) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, thumbnailSize.width, thumbnailSize.height),
    );
    canvas.drawColor(ScrapTheme.background, BlendMode.src);

    final bounds = _contentBounds(strokes);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
      return recorder.endRecording();
    }

    const pad = 24.0;
    final content = bounds.inflate(pad);
    final scale = min(
      thumbnailSize.width / content.width,
      thumbnailSize.height / content.height,
    ).clamp(0.02, 1.0);

    final dx = (thumbnailSize.width - content.width * scale) / 2;
    final dy = (thumbnailSize.height - content.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.translate(-content.left, -content.top);

    for (final stroke in strokes) {
      if (stroke.shapeType != ShapeType.none &&
          stroke.shapeVertices.isNotEmpty) {
        _paintShape(canvas, stroke);
      } else if (stroke.points.isNotEmpty) {
        InkRenderer.paintStroke(canvas, stroke);
      }
    }

    canvas.restore();
    return recorder.endRecording();
  }

  static Rect? _contentBounds(List<Stroke> strokes) {
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
    if (maxX! - minX! < 1) maxX = minX! + 1;
    if (maxY! - minY! < 1) maxY = minY! + 1;
    return Rect.fromLTRB(minX!, minY!, maxX!, maxY!);
  }

  static void _paintShape(Canvas canvas, Stroke stroke) {
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
}
