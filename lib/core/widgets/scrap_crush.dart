import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../theme/scrapyard_theme.dart';

/// Exaggerated "crush" destruction for home-screen cards.
///
/// Snapshots the card's [RepaintBoundary], lifts the bitmap into an overlay,
/// and runs a theatrical squash → wobble → crumple → drop sequence with
/// paper-shard particles and a shockwave ring. [onCrushed] fires as soon as
/// the snapshot is captured so the grid can reflow under the animation.
class ScrapCrush {
  ScrapCrush._();

  static const Duration _duration = Duration(milliseconds: 1150);

  /// Normalized time at which the slam bottoms out (impact frame).
  static const double _impactT = 0.34;

  static Future<void> crush(
    BuildContext context,
    GlobalKey? boundaryKey, {
    required VoidCallback onCrushed,
  }) async {
    final renderObject = boundaryKey?.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.attached) {
      onCrushed();
      return;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (rect.isEmpty) {
      onCrushed();
      return;
    }

    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
    final overlay = Overlay.of(context, rootOverlay: true);
    final ui.Image image;
    try {
      image = await renderObject.toImage(pixelRatio: dpr);
    } catch (_) {
      onCrushed();
      return;
    }

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CrushOverlay(
        image: image,
        rect: rect,
        onDone: () {
          entry.remove();
          image.dispose();
        },
      ),
    );
    overlay.insert(entry);

    onCrushed();
  }
}

class _CrushOverlay extends StatefulWidget {
  final ui.Image image;
  final Rect rect;
  final VoidCallback onDone;

  const _CrushOverlay({
    required this.image,
    required this.rect,
    required this.onDone,
  });

  @override
  State<_CrushOverlay> createState() => _CrushOverlayState();
}

class _CrushOverlayState extends State<_CrushOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Shard> _shards;
  bool _impactFired = false;

  @override
  void initState() {
    super.initState();
    _shards = _Shard.spawn(seed: widget.rect.center.dx.toInt());
    _controller = AnimationController(vsync: this, duration: ScrapCrush._duration)
      ..addListener(_maybeImpactHaptic)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) widget.onDone();
      })
      ..forward();
  }

  void _maybeImpactHaptic() {
    if (!_impactFired && _controller.value >= ScrapCrush._impactT) {
      _impactFired = true;
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final pose = _CrushPose.at(t, widget.rect);

          return Stack(
            children: [
              if (t >= ScrapCrush._impactT)
                Positioned.fromRect(
                  rect: widget.rect,
                  child: CustomPaint(
                    painter: _ShardPainter(
                      shards: _shards,
                      progress:
                          ((t - ScrapCrush._impactT) / (1 - ScrapCrush._impactT))
                              .clamp(0.0, 1.0),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: widget.rect,
                child: Transform.translate(
                  offset: pose.translation,
                  child: Transform.rotate(
                    angle: pose.rotation,
                    child: Transform(
                      alignment: Alignment.bottomCenter,
                      transform: Matrix4.diagonal3Values(
                        pose.scaleX,
                        pose.scaleY,
                        1.0,
                      ),
                      child: Opacity(
                        opacity: pose.opacity,
                        child: RawImage(image: widget.image),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Resolved transform for a given normalized time [t].
class _CrushPose {
  final double scaleX;
  final double scaleY;
  final double rotation;
  final double opacity;
  final Offset translation;

  const _CrushPose({
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
    required this.opacity,
    required this.translation,
  });

  static final _scaleY = TweenSequence<double>([
    // Wind-up: rear back slightly.
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.09)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    // Slam: flattened against the desk.
    TweenSequenceItem(
      tween: Tween(begin: 1.09, end: 0.07)
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 22,
    ),
    // Impact wobble: squashed paper springs back a touch.
    TweenSequenceItem(
      tween: Tween(begin: 0.07, end: 0.20)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 26,
    ),
    TweenSequenceItem(tween: ConstantTween(0.20), weight: 18),
    // Crumple: puff back up into a ball.
    TweenSequenceItem(
      tween:
          Tween(begin: 0.20, end: 0.55).chain(CurveTween(curve: Curves.easeIn)),
      weight: 22,
    ),
  ]);

  static final _scaleX = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.95)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 12,
    ),
    // Bulge sideways as the sheet is flattened.
    TweenSequenceItem(
      tween: Tween(begin: 0.95, end: 1.32)
          .chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 22,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.32, end: 1.06)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 26,
    ),
    TweenSequenceItem(tween: ConstantTween(1.06), weight: 18),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.06, end: 0.55).chain(CurveTween(curve: Curves.easeIn)),
      weight: 22,
    ),
  ]);

  static _CrushPose at(double t, Rect rect) {
    // Rotation: wind-up tilt, decaying wobble after impact, then a spin
    // as the crumpled ball tips over.
    double rotation;
    if (t < 0.12) {
      rotation = -0.05 * Curves.easeOut.transform(t / 0.12);
    } else if (t < ScrapCrush._impactT) {
      rotation = -0.05 *
          (1 -
              Curves.easeInCubic
                  .transform((t - 0.12) / (ScrapCrush._impactT - 0.12)));
    } else if (t < 0.60) {
      final p = (t - ScrapCrush._impactT) / (0.60 - ScrapCrush._impactT);
      rotation = sin(p * pi * 3) * 0.10 * (1 - p);
    } else {
      rotation = 0.55 * Curves.easeIn.transform((t - 0.60) / 0.40);
    }

    // Drop: the crumpled ball rolls off and falls away near the end.
    double fallY = 0;
    if (t > 0.78) {
      final p = Curves.easeInCubic.transform((t - 0.78) / 0.22);
      fallY = p * (rect.height * 0.9 + 90);
    }

    // Sideways tremor right after impact.
    double shakeX = 0;
    if (t >= ScrapCrush._impactT && t < 0.55) {
      final p = (t - ScrapCrush._impactT) / (0.55 - ScrapCrush._impactT);
      shakeX = sin(p * pi * 6) * 3.5 * (1 - p);
    }

    final opacity =
        t < 0.86 ? 1.0 : 1.0 - Curves.easeIn.transform((t - 0.86) / 0.14);

    return _CrushPose(
      scaleX: _scaleX.transform(t),
      scaleY: _scaleY.transform(t),
      rotation: rotation,
      opacity: opacity,
      translation: Offset(shakeX, fallY),
    );
  }
}

class _Shard {
  final Offset direction;
  final double speed;
  final double size;
  final double spin;
  final Color color;

  const _Shard({
    required this.direction,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
  });

  static const _palette = [
    ScrapTheme.cardSurface,
    ScrapTheme.kraft,
    ScrapTheme.tape,
    ScrapTheme.accentSurface,
    ScrapTheme.dividers,
  ];

  static List<_Shard> spawn({required int seed, int count = 16}) {
    final random = Random(seed);
    return List.generate(count, (_) {
      final angle = random.nextDouble() * 2 * pi;
      return _Shard(
        direction: Offset(cos(angle), sin(angle) * 0.6 - 0.35),
        speed: 50 + random.nextDouble() * 220,
        size: 3 + random.nextDouble() * 11,
        spin: (random.nextDouble() - 0.5) * 14,
        color: _palette[random.nextInt(_palette.length)],
      );
    });
  }
}

class _ShardPainter extends CustomPainter {
  final List<_Shard> shards;

  /// 0 at the impact frame, 1 at the end of the animation.
  final double progress;

  _ShardPainter({required this.shards, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.85);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final shard in shards) {
      final dx = shard.direction.dx * shard.speed * progress;
      final dy = shard.direction.dy * shard.speed * progress +
          420 * progress * progress;
      final fade = (1 - progress * 1.15).clamp(0.0, 1.0);
      if (fade <= 0) continue;

      paint.color = shard.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(shard.spin * progress);
      final s = shard.size * (1 - progress * 0.5);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.7),
        paint,
      );
      canvas.restore();
    }

    // Shockwave ring at the moment of impact.
    if (progress < 0.45) {
      final p = progress / 0.45;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * (1 - p)
        ..color = ScrapTheme.mutedText.withValues(alpha: 0.5 * (1 - p));
      canvas.drawCircle(origin, 12 + p * size.width * 0.8, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_ShardPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
