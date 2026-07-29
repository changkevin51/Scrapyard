import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vector recreation of the Scrapyard paper-smiley logo.
///
/// Geometry is authored axis-aligned against the 400×400 SplashLogo asset,
/// then rotated to match the asset tilt.
class LogoPainter extends CustomPainter {
  const LogoPainter({
    this.color = const Color(0xFF1C1C1C),
    this.strokeWidth,
  });

  final Color color;

  /// Override stroke width. When null, matches the PNG (~9px at 400).
  final double? strokeWidth;

  static const double designSize = 400;
  static const double _cx = 200;
  static const double _cy = 200;

  /// Counter-clockwise tilt of the logo in the PNG (radians).
  static const double tilt = -9.5 * math.pi / 180;

  static const double _left = 65.4;
  static const double _right = 337.4;
  static const double _top = 48.5;
  static const double _foldX = 277.0;
  static const double _foldY = 126.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / designSize;
    final dx = (size.width - designSize * scale) / 2;
    final dy = (size.height - designSize * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final paint = strokePaint(color, strokeWidth);
    canvas.drawPath(outlinePath(), paint);
    canvas.drawPath(foldPath(), paint);
    canvas.drawPath(leftEyePath(), paint);
    canvas.drawPath(rightEyePath(), paint);
    canvas.drawPath(mouthPath(), paint);

    canvas.restore();
  }

  static Paint strokePaint(Color color, double? strokeWidth) {
    return Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth ?? 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
  }

  static Offset _r(double x, double y) {
    final cos = math.cos(tilt);
    final sin = math.sin(tilt);
    final dx = x - _cx;
    final dy = y - _cy;
    return Offset(_cx + dx * cos - dy * sin, _cy + dx * sin + dy * cos);
  }

  /// Paper outline: top → dog-ear diagonal → right → torn bottom → left.
  static Path outlinePath() {
    final path = Path();
    void move(double x, double y) {
      final o = _r(x, y);
      path.moveTo(o.dx, o.dy);
    }

    void line(double x, double y) {
      final o = _r(x, y);
      path.lineTo(o.dx, o.dy);
    }

    move(_left, _top);
    line(_foldX, _top);
    line(_right, _foldY);
    line(_right, 310.3);
    line(300.5, 329.7);
    line(275.7, 320.7);
    line(236.0, 340.6);
    line(212.1, 331.6);
    line(176.3, 346.1);
    line(151.5, 337.0);
    line(115.4, 347.4);
    line(92.5, 338.6);
    line(70.8, 347.2);
    line(_left, 350.4);
    path.close();
    return path;
  }

  /// Internal L-shaped fold crease (meets top + right edges).
  static Path foldPath() {
    final path = Path();
    final a = _r(_foldX, _top);
    final b = _r(_foldX, _foldY);
    final c = _r(_right, _foldY);
    path
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy);
    return path;
  }

  static Path leftEyePath() {
    final a = _r(167.2, 170.5);
    final b = _r(167.2, 194.8);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }

  static Path rightEyePath() {
    final a = _r(226.9, 170.5);
    final b = _r(226.9, 194.8);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }

  /// Smile — quadratic through the extracted mouth bottom.
  static Path mouthPath() {
    final a = _r(162.0, 228.3);
    final ctrl = _r(197.0, 258.0);
    final b = _r(232.0, 228.5);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
  }

  static Offset get center => const Offset(_cx, _cy);

  @override
  bool shouldRepaint(covariant LogoPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Draws a [Path] partially along its length (0–1).
Path extractPathProgress(Path source, double progress) {
  final t = progress.clamp(0.0, 1.0);
  if (t <= 0) return Path();
  if (t >= 1) return Path.from(source);

  final out = Path();
  for (final metric in source.computeMetrics()) {
    out.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
  }
  return out;
}

/// Tip position along a path at [progress] (0–1), or null if empty.
Offset? pathTip(Path source, double progress) {
  final t = progress.clamp(0.0, 1.0);
  if (t <= 0) return null;
  for (final metric in source.computeMetrics()) {
    final distance = metric.length * t.clamp(0.0, 1.0);
    final tangent = metric.getTangentForOffset(
      distance.clamp(0.0, metric.length),
    );
    if (tangent != null) return tangent.position;
  }
  return null;
}

/// Full choreography state for the splash-style logo reveal.
class LogoAnimState {
  const LogoAnimState({
    this.outline = 1,
    this.fold = 1,
    this.leftEye = 1,
    this.rightEye = 1,
    this.mouth = 1,
    this.paperScale = 1,
    this.paperTilt = 0,
    this.paperOpacity = 1,
    this.faceScale = 1,
    this.showPen = false,
    this.penAt,
  });

  final double outline;
  final double fold;
  final double leftEye;
  final double rightEye;
  final double mouth;
  final double paperScale;
  final double paperTilt;
  final double paperOpacity;
  final double faceScale;
  final bool showPen;
  final Offset? penAt;

  static const settled = LogoAnimState();
}

/// Maps a single 0–1 controller value into [LogoAnimState].
LogoAnimState logoAnimAt(double t) {
  double seg(double start, double end, Curve curve) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform((t - start) / (end - start));
  }

  final outline = seg(0.00, 0.28, Curves.easeInOutCubic);
  final fold = seg(0.24, 0.34, Curves.easeOutCubic);
  final paperOpacity = seg(0.00, 0.06, Curves.easeOut);

  final leftEye = seg(0.42, 0.54, Curves.easeInOut);
  final rightEye = seg(0.56, 0.68, Curves.easeInOut);
  final mouth = seg(0.70, 0.90, Curves.easeInOutCubic);

  final facePop = seg(0.88, 1.00, Curves.easeOut);
  final faceScale = 1.0 + 0.04 * math.sin(facePop * math.pi);

  Offset? pen;
  var showPen = false;
  if (outline > 0 && outline < 1) {
    pen = pathTip(LogoPainter.outlinePath(), outline);
    showPen = true;
  } else if (fold > 0 && fold < 1) {
    pen = pathTip(LogoPainter.foldPath(), fold);
    showPen = true;
  } else if (leftEye > 0 && leftEye < 1) {
    pen = pathTip(LogoPainter.leftEyePath(), leftEye);
    showPen = true;
  } else if (rightEye > 0 && rightEye < 1) {
    pen = pathTip(LogoPainter.rightEyePath(), rightEye);
    showPen = true;
  } else if (mouth > 0 && mouth < 1) {
    pen = pathTip(LogoPainter.mouthPath(), mouth);
    showPen = true;
  }

  return LogoAnimState(
    outline: outline,
    fold: fold,
    leftEye: leftEye,
    rightEye: rightEye,
    mouth: mouth,
    paperScale: 1,
    paperTilt: 0,
    paperOpacity: paperOpacity,
    faceScale: faceScale,
    showPen: showPen,
    penAt: pen,
  );
}

/// Animated logo painter driven by [LogoAnimState].
class AnimatedLogoPainter extends CustomPainter {
  const AnimatedLogoPainter({
    required this.state,
    this.color = const Color(0xFF1C1C1C),
    this.strokeWidth,
  });

  final LogoAnimState state;
  final Color color;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / LogoPainter.designSize;
    final dx = (size.width - LogoPainter.designSize * scale) / 2;
    final dy = (size.height - LogoPainter.designSize * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final paint = LogoPainter.strokePaint(color, strokeWidth);
    final center = LogoPainter.center;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(state.paperTilt);
    canvas.scale(state.paperScale);
    canvas.translate(-center.dx, -center.dy);

    paint.color = color.withValues(alpha: state.paperOpacity);

    if (state.outline > 0) {
      canvas.drawPath(
        extractPathProgress(LogoPainter.outlinePath(), state.outline),
        paint,
      );
    }
    if (state.fold > 0) {
      canvas.drawPath(
        extractPathProgress(LogoPainter.foldPath(), state.fold),
        paint,
      );
    }
    canvas.restore();

    if (state.leftEye > 0 || state.rightEye > 0 || state.mouth > 0) {
      final faceCenter = _faceCenter();
      canvas.save();
      canvas.translate(faceCenter.dx, faceCenter.dy);
      canvas.scale(state.faceScale);
      canvas.translate(-faceCenter.dx, -faceCenter.dy);
      paint.color = color;

      if (state.leftEye > 0) {
        canvas.drawPath(
          extractPathProgress(LogoPainter.leftEyePath(), state.leftEye),
          paint,
        );
      }
      if (state.rightEye > 0) {
        canvas.drawPath(
          extractPathProgress(LogoPainter.rightEyePath(), state.rightEye),
          paint,
        );
      }
      if (state.mouth > 0) {
        canvas.drawPath(
          extractPathProgress(LogoPainter.mouthPath(), state.mouth),
          paint,
        );
      }
      canvas.restore();
    }

    if (state.showPen && state.penAt != null) {
      final tip = state.penAt!;
      final glow = Paint()
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tip, 7, glow);
      canvas.drawCircle(
        tip,
        3.2,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();
  }

  static Offset? _cachedFaceCenter;

  static Offset _faceCenter() {
    final cached = _cachedFaceCenter;
    if (cached != null) return cached;

    final leftMetric = LogoPainter.leftEyePath().computeMetrics().first;
    final rightMetric = LogoPainter.rightEyePath().computeMetrics().first;
    final mouthMetric = LogoPainter.mouthPath().computeMetrics().first;

    final a = leftMetric.getTangentForOffset(leftMetric.length * 0.5)!.position;
    final b =
        rightMetric.getTangentForOffset(rightMetric.length * 0.5)!.position;
    final m =
        mouthMetric.getTangentForOffset(mouthMetric.length * 0.5)!.position;

    return _cachedFaceCenter = Offset((a.dx + b.dx) / 2, (a.dy + m.dy) / 2);
  }

  @override
  bool shouldRepaint(covariant AnimatedLogoPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
