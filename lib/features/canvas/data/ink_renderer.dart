import 'dart:math';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart' hide StrokePoint;

import '../domain/models/stroke.dart';
import 'pen_engine.dart';
import 'stroke_sampler.dart';

/// Industry-standard stroke renderer.
///
/// Freehand styles (pen / fountain / pencil / marker / inkBrush) use
/// [perfect_freehand] outline polygons — one filled Path per stroke.
/// Calligraphy uses a custom fixed-nib quad-strip polygon.
/// Highlighters use a continuous flat-cap stroke with multiply blending.
class InkRenderer {
  InkRenderer._();

  /// Paint a committed or live stroke.
  static void paint({
    required Canvas canvas,
    required List<StrokePoint> pts,
    required Color color,
    required double baseWidth,
    required PenStyle style,
    required bool isHighlighter,
    double streamline = 0.35,
    double sensitivity = 0.5,
    bool isComplete = true,
    /// When true (PDF overlays), multiply directly with the backdrop so
    /// underlying black text stays crisp instead of washing out.
    bool multiplyWithBackdrop = false,
  }) {
    if (pts.isEmpty) return;

    if (isHighlighter) {
      _paintHighlighter(
        canvas,
        pts,
        color,
        baseWidth,
        streamline: streamline,
        multiplyWithBackdrop: multiplyWithBackdrop,
      );
      return;
    }

    switch (style) {
      case PenStyle.calligraphy:
        _paintNib(canvas, pts, color, baseWidth);
      case PenStyle.pen:
      case PenStyle.fountain:
      case PenStyle.ballpoint:
      case PenStyle.pencil:
      case PenStyle.marker:
      case PenStyle.inkBrush:
        _paintFreehand(
          canvas, pts, color, baseWidth, style,
          streamline: streamline,
          sensitivity: sensitivity,
          isComplete: isComplete,
        );
    }
  }

  /// Convenience for painting a full [Stroke] object.
  static void paintStroke(
    Canvas canvas,
    Stroke stroke, {
    double streamline = 0.35,
    double sensitivity = 0.5,
    bool multiplyWithBackdrop = false,
  }) {
    paint(
      canvas: canvas,
      pts: stroke.points,
      color: stroke.color,
      baseWidth: stroke.baseWidth,
      style: stroke.penStyle,
      isHighlighter: stroke.isHighlighter,
      streamline: streamline,
      sensitivity: sensitivity,
      isComplete: true,
      multiplyWithBackdrop: multiplyWithBackdrop,
    );
  }

  /// S-wave preview for the settings panel.
  static void paintPreview(
    Canvas canvas,
    Size size,
    Color color,
    PenStyle style, {
    double baseWidth = 1.8,
    double sensitivity = 0.5,
  }) {
    final pts = <StrokePoint>[];
    final w = size.width;
    final h = size.height;
    const n = 60;
    for (int i = 0; i < n; i++) {
      final t = i / (n - 1);
      final x = t * w;
      final y = h / 2 + sin(t * 3 * pi) * (h * 0.32);
      final pr = 0.4 + 0.6 * sin(t * pi);
      pts.add(StrokePoint(
        x: x,
        y: y,
        pressure: pr,
        timestamp: i * 16000, // microseconds
      ));
    }
    paint(
      canvas: canvas,
      pts: pts,
      color: color,
      baseWidth: baseWidth,
      style: style,
      isHighlighter: false,
      sensitivity: sensitivity,
      isComplete: true,
    );
  }

  // ─── Freehand via perfect_freehand ───────────────────────────

  static void _paintFreehand(
    Canvas canvas,
    List<StrokePoint> pts,
    Color color,
    double baseWidth,
    PenStyle style, {
    required double streamline,
    required double sensitivity,
    required bool isComplete,
  }) {
    final options = _optionsFor(
      style,
      baseWidth,
      streamline: streamline,
      sensitivity: sensitivity,
      isComplete: isComplete,
    );

    final fitted = catmullRomResample(pts, spacing: 2.0);
    final vectors = <PointVector>[
      for (final p in fitted)
        PointVector(p.x, p.y, p.pressure.clamp(0.0, 1.0)),
    ];

    // Duplicate single-point taps so perfect_freehand produces a visible dot.
    if (vectors.length == 1) {
      vectors.add(PointVector(
        vectors.first.x + 0.01,
        vectors.first.y + 0.01,
        vectors.first.pressure,
      ));
    }

    final outline = getStroke(vectors, options: options);
    if (outline.isEmpty) return;

    final path = _smoothClosedPolygon([
      for (final p in outline) Offset(p.dx, p.dy),
    ]);

    final paint = Paint()
      ..color = _colorForStyle(color, style)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
  }

  static StrokeOptions _optionsFor(
    PenStyle style,
    double baseWidth, {
    required double streamline,
    required double sensitivity,
    required bool isComplete,
  }) {
    final sl = streamline.clamp(0.0, 0.65);
    switch (style) {
      case PenStyle.pen:
        // Pressure response — at 100% sensitivity thinning reaches ~0.6.
        return StrokeOptions(
          size: baseWidth * 2.2,
          thinning: (sensitivity * 0.6).clamp(0.0, 0.6),
          smoothing: 0.45,
          streamline: sl,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: false),
        );
      case PenStyle.fountain:
        // Same profile as pen, but pressure thinning is heavily exaggerated.
        return StrokeOptions(
          size: baseWidth * 2.2,
          thinning: (0.85 + sensitivity * 0.15).clamp(0.85, 1.0),
          smoothing: 0.45,
          streamline: sl,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: false),
        );
      case PenStyle.ballpoint:
        // Constant width — same as the former Pen profile.
        return StrokeOptions(
          size: baseWidth * 2.2,
          thinning: 0,
          smoothing: 0.45,
          streamline: sl,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: false),
        );
      case PenStyle.marker:
        return StrokeOptions(
          size: baseWidth * 2.8,
          thinning: 0,
          smoothing: 0.35,
          streamline: sl * 0.7,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: false, taperEnabled: false),
          end: StrokeEndOptions.end(cap: false, taperEnabled: false),
        );
      case PenStyle.pencil:
        return StrokeOptions(
          size: baseWidth * 1.6,
          thinning: sensitivity.clamp(0.0, 1.0),
          smoothing: 0.25,
          streamline: sl * 0.6,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: true, taperEnabled: false),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        );
      case PenStyle.inkBrush:
        return StrokeOptions(
          size: baseWidth * 3.5,
          thinning: (0.4 + sensitivity * 0.6).clamp(0.0, 1.0),
          smoothing: 0.5,
          streamline: sl,
          simulatePressure: false,
          isComplete: isComplete,
          start: StrokeEndOptions.start(cap: true, taperEnabled: true),
          end: StrokeEndOptions.end(cap: true, taperEnabled: true),
        );
      case PenStyle.calligraphy:
        // Unreachable — calligraphy uses _paintNib.
        return StrokeOptions(size: baseWidth * 2);
    }
  }

  static Color _colorForStyle(Color color, PenStyle style) {
    // [color.a] carries concentration — keep it literal (100% = fully opaque).
    final conc = color.a.clamp(0.0, 1.0);
    if (style == PenStyle.pencil) {
      final hsl = HSLColor.fromColor(color);
      return hsl
          .withSaturation(hsl.saturation * 0.2)
          .withLightness((hsl.lightness * 0.5 + 0.2).clamp(0.0, 1.0))
          .toColor()
          .withValues(alpha: conc);
    }
    if (style == PenStyle.marker || style == PenStyle.inkBrush) {
      return color.withValues(alpha: conc);
    }
    return color;
  }

  // ─── Nib quad-strip (calligraphy) ────────────────────────────

  static void _paintNib(
    Canvas canvas,
    List<StrokePoint> rawPts,
    Color color,
    double baseWidth,
  ) {
    final pts = catmullRomResample(rawPts, spacing: 2.0);
    if (pts.isEmpty) return;
    if (pts.length < 2) {
      // Single-point tap → small filled oval
      final p = pts.first;
      final r = baseWidth * 0.6;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(p.x, p.y), width: r * 2, height: r),
        Paint()..color = color..style = PaintingStyle.fill,
      );
      return;
    }

    const fixedNibAngle = pi / 4; // 45°
    final nibDir = Offset(cos(fixedNibAngle), sin(fixedNibAngle));

    final left = <Offset>[];
    final right = <Offset>[];

    for (int i = 0; i < pts.length; i++) {
      final p = Offset(pts[i].x, pts[i].y);
      final press = pts[i].pressure.clamp(0.0, 1.0);

      // Stroke direction
      Offset dir;
      if (i == 0) {
        dir = Offset(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
      } else if (i == pts.length - 1) {
        dir = Offset(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
      } else {
        dir = Offset(pts[i + 1].x - pts[i - 1].x, pts[i + 1].y - pts[i - 1].y);
      }
      final len = dir.distance;
      final strokeDir = len > 0.01 ? dir / len : const Offset(1, 0);
      final cross = (strokeDir.dx * nibDir.dy - strokeDir.dy * nibDir.dx).abs();

      final halfW = (baseWidth * 0.08 + baseWidth * 1.3 * cross) *
          (0.5 + press * 0.5);

      final hw = max(0.3, halfW);
      // Offset along the nib for classic flat-nib look
      final nibOffset = nibDir * hw;

      left.add(p + nibOffset);
      right.add(p - nibOffset);
    }

    // Smooth closed strip: quadratic through midpoints along each nib edge.
    final path = Path();
    _addSmoothPolyline(path, left, moveToFirst: true);
    _addSmoothPolyline(
      path,
      [for (var i = right.length - 1; i >= 0; i--) right[i]],
      moveToFirst: false,
    );
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  // ─── Highlighter ─────────────────────────────────────────────

  static void _paintHighlighter(
    Canvas canvas,
    List<StrokePoint> pts,
    Color color,
    double baseWidth, {
    double streamline = 0.35,
    bool multiplyWithBackdrop = false,
  }) {
    if (pts.isEmpty) return;

    final smoothed = _streamlinePoints(pts, streamline);

    final path = Path();
    if (smoothed.length == 1) {
      path.moveTo(smoothed.first.x, smoothed.first.y);
      path.lineTo(smoothed.first.x + 0.01, smoothed.first.y);
    } else {
      path.moveTo(smoothed.first.x, smoothed.first.y);
      for (int i = 1; i < smoothed.length - 1; i++) {
        final mid = Offset(
          (smoothed[i].x + smoothed[i + 1].x) / 2,
          (smoothed[i].y + smoothed[i + 1].y) / 2,
        );
        path.quadraticBezierTo(
          smoothed[i].x,
          smoothed[i].y,
          mid.dx,
          mid.dy,
        );
      }
      path.lineTo(smoothed.last.x, smoothed.last.y);
    }

    // Concentration is baked into color.a — 100% means full mark strength.
    final markAlpha = color.a.clamp(0.02, 1.0);
    final stroke = Paint()
      ..color = color.withValues(alpha: markAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (multiplyWithBackdrop) {
      // Composite multiply against whatever is already on the destination
      // (e.g. PDF page pixels under a page overlay).
      stroke.blendMode = BlendMode.multiply;
      canvas.drawPath(path, stroke);
      return;
    }

    final bounds = path.getBounds().inflate(baseWidth);
    canvas.saveLayer(
      bounds,
      Paint()..blendMode = BlendMode.multiply,
    );
    canvas.drawPath(path, stroke);
    canvas.restore();
  }

  /// Closed midpoint-quadratic path so outline polygons are round, not faceted.
  static Path _smoothClosedPolygon(List<Offset> pts) {
    if (pts.length < 3) {
      return Path()..addPolygon(pts, true);
    }
    final n = pts.length;
    final startMid = Offset(
      (pts[n - 1].dx + pts[0].dx) / 2,
      (pts[n - 1].dy + pts[0].dy) / 2,
    );
    final path = Path()..moveTo(startMid.dx, startMid.dy);
    for (var i = 0; i < n; i++) {
      final curr = pts[i];
      final next = pts[(i + 1) % n];
      final mid = Offset((curr.dx + next.dx) / 2, (curr.dy + next.dy) / 2);
      path.quadraticBezierTo(curr.dx, curr.dy, mid.dx, mid.dy);
    }
    path.close();
    return path;
  }

  /// Midpoint-quadratic polyline (same as highlighter / torn-edge paths).
  static void _addSmoothPolyline(
    Path path,
    List<Offset> pts, {
    required bool moveToFirst,
  }) {
    if (pts.isEmpty) return;
    if (moveToFirst) {
      path.moveTo(pts.first.dx, pts.first.dy);
    } else {
      path.lineTo(pts.first.dx, pts.first.dy);
    }
    if (pts.length == 1) return;
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return;
    }
    final firstMid = Offset(
      (pts[0].dx + pts[1].dx) / 2,
      (pts[0].dy + pts[1].dy) / 2,
    );
    path.lineTo(firstMid.dx, firstMid.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset(
        (pts[i].dx + pts[i + 1].dx) / 2,
        (pts[i].dy + pts[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
  }

  /// Exponential moving-average smooth — mirrors freehand streamline feel.
  static List<StrokePoint> _streamlinePoints(
    List<StrokePoint> pts,
    double streamline,
  ) {
    if (pts.length < 2 || streamline <= 0) return pts;
    final t = (streamline / 0.65).clamp(0.0, 1.0);
    // Higher streamline → smaller keep factor → smoother path.
    final keep = 1.0 - (t * 0.82);
    final out = <StrokePoint>[pts.first];
    var x = pts.first.x;
    var y = pts.first.y;
    for (var i = 1; i < pts.length; i++) {
      x += (pts[i].x - x) * keep;
      y += (pts[i].y - y) * keep;
      out.add(StrokePoint(
        x: x,
        y: y,
        pressure: pts[i].pressure,
        timestamp: pts[i].timestamp,
      ));
    }
    return out;
  }

  /// Compute axis-aligned bounds for a stroke's points.
  static Rect boundsOf(List<StrokePoint> pts, {double pad = 0}) {
    if (pts.isEmpty) return Rect.zero;
    double minX = pts.first.x, maxX = pts.first.x;
    double minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(pad);
  }
}

/// Re-export for callers that previously used StrokeRenderer.
typedef StrokeRenderer = InkRenderer;
