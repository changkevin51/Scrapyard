import 'package:flutter/material.dart';

/// Chisel-tip highlighter marker — fat barrel, slanted nib.
class HighlighterIcon extends StatelessWidget {
  final double size;
  final Color color;

  const HighlighterIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HighlighterIconPainter(color)),
    );
  }
}

class _HighlighterIconPainter extends CustomPainter {
  final Color color;
  const _HighlighterIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final nib = Path()
      ..moveTo(w * 0.171, h * 0.671)
      ..lineTo(w * 0.270, h * 0.770)
      ..lineTo(w * 0.157, h * 0.883)
      ..lineTo(w * 0.128, h * 0.714)
      ..close();
    canvas.drawPath(
      nib,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(nib, stroke);

    final barrel = Path()
      ..moveTo(w * 0.667, h * 0.047)
      ..lineTo(w * 0.893, h * 0.273)
      ..lineTo(w * 0.493, h * 0.673)
      ..lineTo(w * 0.267, h * 0.447)
      ..close();
    canvas.drawPath(barrel, stroke);

    canvas.drawLine(
        Offset(w * 0.267, h * 0.447), Offset(w * 0.171, h * 0.671), stroke);
    canvas.drawLine(
        Offset(w * 0.493, h * 0.673), Offset(w * 0.270, h * 0.770), stroke);
  }

  @override
  bool shouldRepaint(covariant _HighlighterIconPainter old) =>
      old.color != color;
}

/// Classic angled rubber eraser — outlined to match other toolbar tools.
class EraserIcon extends StatelessWidget {
  final double size;
  final Color color;

  const EraserIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EraserIconPainter(color)),
    );
  }
}

class _EraserIconPainter extends CustomPainter {
  final Color color;
  const _EraserIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final a = Offset(w * 0.52, h * 0.16);
    final b = Offset(w * 0.84, h * 0.30);
    final c = Offset(w * 0.50, h * 0.84);
    final d = Offset(w * 0.18, h * 0.70);

    final midLeft = Offset.lerp(a, d, 0.38)!;
    final midRight = Offset.lerp(b, c, 0.38)!;

    final shade = Path()
      ..moveTo(midLeft.dx, midLeft.dy)
      ..lineTo(midRight.dx, midRight.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(
      shade,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );

    final body = Path()
      ..moveTo(d.dx, d.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close();
    canvas.drawPath(body, stroke);

    canvas.drawLine(midLeft, midRight, stroke..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _EraserIconPainter old) => old.color != color;
}
