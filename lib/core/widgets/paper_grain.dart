import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/scrapyard_theme.dart';

/// Soft paper grain overlay.
///
/// Builds a tiny 64×64 noise tile once, caches it, and tiles it with an
/// ImageShader so paint cost is a single rectangle — not hundreds of circles.
class PaperGrain extends StatefulWidget {
  final double opacity;
  final int seed;

  const PaperGrain({
    super.key,
    this.opacity = 0.035,
    this.seed = 42,
  });

  @override
  State<PaperGrain> createState() => _PaperGrainState();
}

class _PaperGrainState extends State<PaperGrain> {
  ui.Image? _tile;

  static String? _cachedKey;
  static ui.Image? _cachedImage;

  @override
  void initState() {
    super.initState();
    _ensureTile();
  }

  @override
  void didUpdateWidget(covariant PaperGrain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed || oldWidget.opacity != widget.opacity) {
      _ensureTile();
    }
  }

  Future<void> _ensureTile() async {
    final key = '${widget.seed}_${widget.opacity.toStringAsFixed(3)}';
    if (_cachedKey == key && _cachedImage != null) {
      if (mounted) setState(() => _tile = _cachedImage);
      return;
    }
    final image = await _buildTile(widget.seed, widget.opacity);
    _cachedKey = key;
    _cachedImage = image;
    if (mounted) setState(() => _tile = image);
  }

  static Future<ui.Image> _buildTile(int seed, double opacity) async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var x = seed.toDouble();
    double next() {
      x = (x * 1103515245 + 12345) % 2147483648;
      return x / 2147483648;
    }

    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 28; i++) {
      final px = next() * size;
      final py = next() * size;
      final r = 0.3 + next() * 0.7;
      paint.color = ScrapTheme.primaryText.withValues(
        alpha: opacity * (0.35 + next() * 0.65),
      );
      canvas.drawCircle(Offset(px, py), r, paint);
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size.toInt(), size.toInt());
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile;
    if (tile == null) return const SizedBox.expand();
    return IgnorePointer(
      child: CustomPaint(
        painter: _TiledGrainPainter(tile),
        isComplex: true,
        willChange: false,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TiledGrainPainter extends CustomPainter {
  final ui.Image tile;

  _TiledGrainPainter(this.tile);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      )
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _TiledGrainPainter oldDelegate) =>
      oldDelegate.tile != tile;
}
