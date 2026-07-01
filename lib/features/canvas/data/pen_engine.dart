import 'dart:math';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// Pen Style — defines the visual character of the stroke rendering
// ─────────────────────────────────────────────────────────────────
enum PenStyle {
  normal,       // Cubic Catmull-Rom — the default smooth pen
  calligraphy,  // Fixed-nib calligraphy: thick downstrokes, thin crossstrokes
  fountain,     // Flexible fountain pen: organic nib-angle variation
  brush,        // Ink brush: high pressure sensitivity, heavy taper
  pencil,       // Graphite pencil: thin, textured, desaturated
  marker,       // Felt-tip marker: consistent width, slight transparency
  chalk,        // Chalk on board: rough, broken edges, dusty
  ballpoint,    // Ballpoint: very thin, uniform, precise
}

extension PenStyleInfo on PenStyle {
  String get label => switch (this) {
    PenStyle.normal        => 'Pen',
    PenStyle.calligraphy   => 'Calligraphy',
    PenStyle.fountain      => 'Fountain',
    PenStyle.brush         => 'Brush',
    PenStyle.pencil        => 'Pencil',
    PenStyle.marker        => 'Marker',
    PenStyle.chalk         => 'Chalk',
    PenStyle.ballpoint     => 'Ballpoint',
  };

  String get kanji => switch (this) {
    PenStyle.normal        => '筆',
    PenStyle.calligraphy   => '書',
    PenStyle.fountain      => '泉',
    PenStyle.brush         => '刷',
    PenStyle.pencil        => '鉛',
    PenStyle.marker        => '印',
    PenStyle.chalk         => '粉',
    PenStyle.ballpoint     => '珠',
  };

  String get description => switch (this) {
    PenStyle.normal        => 'Smooth cubic Bézier ink',
    PenStyle.calligraphy   => 'Thick & thin nib strokes',
    PenStyle.fountain      => 'Flexible nib, organic flow',
    PenStyle.brush         => 'Ink brush, pressure-heavy',
    PenStyle.pencil        => 'Graphite feel, textured',
    PenStyle.marker        => 'Felt-tip, consistent width',
    PenStyle.chalk         => 'Rough, dusty chalk edges',
    PenStyle.ballpoint     => 'Ultra-fine, precise line',
  };
}

// ─────────────────────────────────────────────────────────────────
// Pen settings model — extended with PenStyle
// ─────────────────────────────────────────────────────────────────
class PenSettings {
  /// Lazy-rope stabilization strength (0 = raw, 1 = max smoothing)
  final double stability;

  /// Ink concentration / opacity (0.1 = very light, 1.0 = full)
  final double concentration;

  /// Apply Bézier beautification to new strokes (baked per-stroke)
  final bool beautify;

  /// Show faint velocity-based prediction ghost ahead of stroke
  final bool predict;

  /// Pen style — affects the visual rendering algorithm
  final PenStyle penStyle;

  const PenSettings({
    this.stability    = 0.45,
    this.concentration = 1.0,
    this.beautify     = true,
    this.predict      = false,
    this.penStyle     = PenStyle.normal,
  });

  PenSettings copyWith({
    double?   stability,
    double?   concentration,
    bool?     beautify,
    bool?     predict,
    PenStyle? penStyle,
  }) => PenSettings(
    stability:     stability     ?? this.stability,
    concentration: concentration ?? this.concentration,
    beautify:      beautify      ?? this.beautify,
    predict:       predict       ?? this.predict,
    penStyle:      penStyle      ?? this.penStyle,
  );

  /// Effective color with concentration baked into alpha
  Color effectiveColor(Color base) =>
      base.withValues(alpha: concentration.clamp(0.05, 1.0));
}

// ─────────────────────────────────────────────────────────────────
// Stroke stabilizer — Lazy Rope algorithm
// ─────────────────────────────────────────────────────────────────
class StrokeStabilizer {
  Offset? _lazyPoint;
  final List<Offset> _smoothBuf = [];
  static const int _smoothWindow = 3;

  void start(Offset point) {
    _lazyPoint = point;
    _smoothBuf..clear()..add(point);
  }

  Offset? process(Offset input, double stability) {
    if (_lazyPoint == null) { start(input); return input; }
    if (stability < 0.02)   { _lazyPoint = input; return input; }

    final ropeLength = stability * 50.0;
    final dist       = (input - _lazyPoint!).distance;

    if (dist > ropeLength) {
      final ratio = (dist - ropeLength) / dist;
      _lazyPoint = _lazyPoint! + (input - _lazyPoint!) * ratio;

      _smoothBuf.add(_lazyPoint!);
      if (_smoothBuf.length > _smoothWindow) _smoothBuf.removeAt(0);

      var sx = 0.0, sy = 0.0;
      for (final p in _smoothBuf) { sx += p.dx; sy += p.dy; }
      return Offset(sx / _smoothBuf.length, sy / _smoothBuf.length);
    }
    return null;
  }

  void reset() { _lazyPoint = null; _smoothBuf.clear(); }
}

// ─────────────────────────────────────────────────────────────────
// StrokeRenderer — renders a stroke segment with the correct style
// Designed to be called once per segment inside a saved-stroke pass.
// ─────────────────────────────────────────────────────────────────
class StrokeRenderer {

  /// Render all segments of a saved stroke using the given [PenStyle].
  static void paintStyled({
    required Canvas canvas,
    required List<dynamic> pts,     // List<StrokePoint>
    required Color color,
    required double baseWidth,
    required PenStyle style,
    required bool isHighlighter,
  }) {
    switch (style) {
      case PenStyle.normal:
        _paintNormal(canvas, pts, color, baseWidth, isHighlighter);
      case PenStyle.calligraphy:
        _paintCalligraphy(canvas, pts, color, baseWidth, false);
      case PenStyle.fountain:
        _paintFountain(canvas, pts, color, baseWidth, false);
      case PenStyle.brush:
        _paintBrush(canvas, pts, color, baseWidth);
      case PenStyle.pencil:
        _paintPencil(canvas, pts, color, baseWidth);
      case PenStyle.marker:
        _paintMarker(canvas, pts, color, baseWidth);
      case PenStyle.chalk:
        _paintChalk(canvas, pts, color, baseWidth);
      case PenStyle.ballpoint:
        _paintBallpoint(canvas, pts, color, baseWidth);
    }
  }

  // ─── Normal: cubic Catmull-Rom + taper ───────────────────────
  static void _paintNormal(Canvas c, List pts, Color color,
      double base, bool isHL) {
    final n = pts.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = isHL ? color.withValues(alpha: 0.30) : color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (isHL) paint.blendMode = BlendMode.multiply;

    for (int i = 0; i < n - 1; i++) {
      final p0 = i > 0   ? Offset(pts[i-1].x, pts[i-1].y) : Offset(pts[i].x, pts[i].y);
      final p1 =            Offset(pts[i].x,   pts[i].y);
      final p2 =            Offset(pts[i+1].x, pts[i+1].y);
      final p3 = i+2 < n ? Offset(pts[i+2].x, pts[i+2].y) : p2;

      final cp1 = p1 + (p2 - p0) * (1.0 / 6.0);
      final cp2 = p2 - (p3 - p1) * (1.0 / 6.0);

      final prog   = i / n;
      final taper  = min(1.0, max(0.15, min(prog, 1 - prog) / 0.12));
      final dt     = max<int>(1, (pts[i+1].timestamp - pts[i].timestamp).toInt());
      final spd    = (p2 - p1).distance / dt;
      final spdFactor = max(0.4, 1.0 - spd * 0.4).clamp(0.4, 1.0);
      final press  = (pts[i].pressure + pts[i+1].pressure) / 2;
      paint.strokeWidth = max(0.4, min(9.0, base * taper * spdFactor * (0.25 + press * 1.8)));
      c.drawPath(Path()..moveTo(p1.dx, p1.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy), paint);
    }
  }

  // ─── Calligraphy: fixed 45° nib, angle → width ───────────────
  // Thick perpendicular-to-nib strokes, thin parallel strokes.
  static void _paintCalligraphy(Canvas c, List pts, Color color,
      double base, bool _) {
    final n = pts.length;
    if (n < 2) return;
    const nibAngle = pi / 4; // 45° nib
    final nibDir = Offset(cos(nibAngle), sin(nibAngle));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < n - 1; i++) {
      final p1 = Offset(pts[i].x,   pts[i].y);
      final p2 = Offset(pts[i+1].x, pts[i+1].y);
      final diff = p2 - p1;
      final len  = diff.distance;
      if (len < 0.5) continue;

      // Cross product with nib gives the sin of angle between stroke and nib
      final strokeDir = diff / len;
      final crossMag  = (strokeDir.dx * nibDir.dy - strokeDir.dy * nibDir.dx).abs();

      // Taper
      final prog  = i / n;
      final taper = min(1.0, max(0.1, min(prog, 1 - prog) / 0.08));
      final press = (pts[i].pressure + pts[i+1].pressure) / 2;

      // Width: thin on parallel strokes → thick on perpendicular
      final w = (base * 0.1 + base * 2.4 * crossMag) * taper * (0.5 + press * 0.5);
      paint.strokeWidth = max(0.3, min(base * 4, w));

      c.drawLine(p1, p2, paint);
    }
  }

  // ─── Fountain pen: dynamic nib angle + ink swell ─────────────
  // Nib angle follows stroke direction changes organically.
  static void _paintFountain(Canvas c, List pts, Color color,
      double base, bool _) {
    final n = pts.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Cumulative nib angle — rotates to follow stroke direction with damping
    double nibAngle = pi / 5; // start angle

    for (int i = 0; i < n - 1; i++) {
      final p0 = i > 0   ? Offset(pts[i-1].x, pts[i-1].y) : Offset(pts[i].x, pts[i].y);
      final p1 =            Offset(pts[i].x,   pts[i].y);
      final p2 =            Offset(pts[i+1].x, pts[i+1].y);
      final p3 = i+2 < n ? Offset(pts[i+2].x, pts[i+2].y) : p2;

      // Cubic control points
      final cp1 = p1 + (p2 - p0) * (1.0 / 6.0);
      final cp2 = p2 - (p3 - p1) * (1.0 / 6.0);

      // Stroke direction angle
      final diff = p2 - p1;
      if (diff.distance > 0.5) {
        final strokeAngle = atan2(diff.dy, diff.dx);
        // Nib slowly rotates toward stroke direction (damping factor 0.2)
        nibAngle = nibAngle + (strokeAngle - nibAngle) * 0.2;
      }

      final nibDir = Offset(cos(nibAngle), sin(nibAngle));
      final strokeNorm = diff.distance > 0 ? diff / diff.distance : const Offset(1, 0);
      final cross = (strokeNorm.dx * nibDir.dy - strokeNorm.dy * nibDir.dx).abs();

      final prog  = i / n;
      final taper = min(1.0, max(0.08, min(prog, 1 - prog) / 0.10));
      final press = (pts[i].pressure + pts[i+1].pressure) / 2;

      // Fountain ink swell on slow, pressing strokes
      final dt    = max<int>(1, (pts[i+1].timestamp - pts[i].timestamp).toInt());
      final spd   = diff.distance / dt;
      final swell = max(0.6, 1.0 - spd * 0.3);

      final w = (base * 0.15 + base * 2.0 * cross) * taper * (0.4 + press * 0.8) * swell;
      paint.strokeWidth = max(0.3, min(base * 3.5, w));

      c.drawPath(Path()..moveTo(p1.dx, p1.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy), paint);
    }
  }

  // ─── Brush: heavy pressure, big taper, ink saturation ────────
  static void _paintBrush(Canvas c, List pts, Color color, double base) {
    final n = pts.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (int i = 0; i < n - 1; i++) {
      final p0 = i > 0   ? Offset(pts[i-1].x, pts[i-1].y) : Offset(pts[i].x, pts[i].y);
      final p1 =            Offset(pts[i].x,   pts[i].y);
      final p2 =            Offset(pts[i+1].x, pts[i+1].y);
      final p3 = i+2 < n ? Offset(pts[i+2].x, pts[i+2].y) : p2;

      final cp1 = p1 + (p2 - p0) * (1.0 / 6.0);
      final cp2 = p2 - (p3 - p1) * (1.0 / 6.0);

      // Heavy taper (first/last 25%)
      final prog  = i / n;
      final taper = min(1.0, max(0.02, min(prog, 1 - prog) / 0.20));
      final press = (pts[i].pressure + pts[i+1].pressure) / 2;

      // Brush is much wider and more pressure-sensitive
      final w = base * 0.8 * taper * (0.1 + press * 3.0);
      paint.strokeWidth = max(0.5, min(base * 6, w));

      c.drawPath(Path()..moveTo(p1.dx, p1.dy)
          ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy), paint);
    }
  }

  // ─── Pencil: thin, textured, slightly erratic ─────────────────
  static void _paintPencil(Canvas c, List pts, Color color, double base) {
    final n = pts.length;
    if (n < 2) return;
    final rng   = Random(42); // seeded for deterministic texture
    // Desaturate the color toward gray
    final hsl    = HSLColor.fromColor(color);
    final grayColor = hsl.withSaturation(hsl.saturation * 0.2)
                         .withLightness((hsl.lightness * 0.5 + 0.2).clamp(0.0, 1.0))
                         .toColor().withValues(alpha: 0.75);

    final paint = Paint()
      ..color = grayColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < n - 1; i++) {
      final p1 = Offset(pts[i].x,   pts[i].y);
      final p2 = Offset(pts[i+1].x, pts[i+1].y);

      // Tiny texture jitter (±0.8px) simulates graphite grain
      final jx = (rng.nextDouble() - 0.5) * 1.6;
      final jy = (rng.nextDouble() - 0.5) * 1.6;
      final jp2 = p2 + Offset(jx, jy);

      // Sinusoidal width variation simulates uneven graphite deposit
      final texWave = 1.0 + 0.3 * sin(i * 0.7);
      final press   = (pts[i].pressure + pts[i+1].pressure) / 2;
      final w = max(0.3, min(base * 1.2, base * 0.4 * texWave * (0.5 + press)));
      paint.strokeWidth = w;

      c.drawLine(p1, jp2, paint);
    }
  }

  // ─── Marker: consistent width, slight transparency ─────────────
  static void _paintMarker(Canvas c, List pts, Color color, double base) {
    final n = pts.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square    // flat cap like a felt tip
      ..strokeJoin = StrokeJoin.bevel
      ..strokeWidth = base * 1.4;      // fixed width — pressure barely matters
    if (n >= 2) {
      final path = Path()..moveTo(pts[0].x, pts[0].y);
      for (int i = 1; i < n; i++) path.lineTo(pts[i].x, pts[i].y);
      c.drawPath(path, paint);
    }
  }

  // ─── Chalk: rough, multi-pass, broken edges ────────────────────
  static void _paintChalk(Canvas c, List pts, Color color, double base) {
    final n = pts.length;
    if (n < 2) return;
    final rng = Random(77);
    // Chalk is usually light on dark, or muted on light
    final hsl = HSLColor.fromColor(color);
    final chalkColor = hsl.withSaturation(hsl.saturation * 0.3)
                          .withLightness((hsl.lightness + 0.3).clamp(0.0, 1.0))
                          .toColor();

    // Draw 3 offset passes at reduced opacity for rough chalk texture
    for (int pass = 0; pass < 3; pass++) {
      final paint = Paint()
        ..color = chalkColor.withValues(alpha: 0.30 + pass * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = base * (0.6 + pass * 0.3);

      final path = Path();
      bool started = false;
      for (int i = 0; i < n; i++) {
        // Randomly skip ~15% of segments to create chalk break effect
        if (rng.nextDouble() < 0.12 && i > 0) { started = false; continue; }
        // Small random offset per pass
        final ox = (rng.nextDouble() - 0.5) * base * 0.6;
        final oy = (rng.nextDouble() - 0.5) * base * 0.6;
        final pt = Offset(pts[i].x + ox, pts[i].y + oy);
        if (!started) { path.moveTo(pt.dx, pt.dy); started = true; }
        else          { path.lineTo(pt.dx, pt.dy); }
      }
      c.drawPath(path, paint);
    }
  }

  // ─── Ballpoint: ultra-thin, uniform, high-precision ──────────
  static void _paintBallpoint(Canvas c, List pts, Color color, double base) {
    final n = pts.length;
    if (n < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = max(0.6, min(1.4, base * 0.4)); // very thin, uniform

    // Single smooth path
    final path = Path()..moveTo(pts[0].x, pts[0].y);
    for (int i = 1; i < n - 1; i++) {
      // Quadratic average-midpoint for smooth curves (fast)
      final mid = Offset((pts[i].x + pts[i+1].x) / 2, (pts[i].y + pts[i+1].y) / 2);
      path.quadraticBezierTo(pts[i].x, pts[i].y, mid.dx, mid.dy);
    }
    if (n > 1) path.lineTo(pts.last.x, pts.last.y);
    c.drawPath(path, paint);
  }

  /// Quick sample preview painter — renders a horizontal S-wave
  /// of sample points in the given style for the settings panel.
  static void paintPreview(Canvas canvas, Size size, Color color,
      PenStyle style, double baseWidth) {
    // Generate a smooth S-wave of sample points
    final pts = <({double x, double y, double pressure, int timestamp})>[];
    final w = size.width, h = size.height;
    final n = 60;
    for (int i = 0; i < n; i++) {
      final t  = i / (n - 1);
      final x  = t * w;
      final y  = h / 2 + sin(t * 3 * pi) * (h * 0.32);
      // Pressure varies along path for realistic preview
      final pr = 0.4 + 0.6 * sin(t * pi);
      pts.add((x: x, y: y, pressure: pr, timestamp: i * 16));
    }
    paintStyled(
      canvas: canvas, pts: pts,
      color: color, baseWidth: baseWidth,
      style: style, isHighlighter: false,
    );
  }
}
