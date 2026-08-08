import 'package:flutter/material.dart';

/// Pan/zoom state for infinite canvas in world coordinates.
///
/// [pan] is the world-space point currently at the screen origin (top-left).
/// [scale] maps world → screen: `screen = (world - pan) * scale`.
class CanvasViewport {
  final Offset pan;
  final double scale;

  const CanvasViewport({
    this.pan = Offset.zero,
    this.scale = 1.0,
  });

  static const double minScaleInfinite = 0.1;
  static const double maxScaleInfinite = 8.0;
  static const double minScaleFinite = 0.5;
  static const double maxScaleFinite = 3.0;

  Offset toWorld(Offset screen) => screen / scale + pan;

  Offset toScreen(Offset world) => (world - pan) * scale;

  Rect visibleWorld(Size viewportSize) => Rect.fromLTWH(
        pan.dx,
        pan.dy,
        viewportSize.width / scale,
        viewportSize.height / scale,
      );

  /// Maps world → screen. Applied as: scale, then translate(-pan).
  Matrix4 get matrix => Matrix4.identity()
    ..scaleByDouble(scale, scale, scale, 1.0)
    ..translateByDouble(-pan.dx, -pan.dy, 0, 1.0);

  CanvasViewport copyWith({Offset? pan, double? scale}) => CanvasViewport(
        pan: pan ?? this.pan,
        scale: scale ?? this.scale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasViewport && pan == other.pan && scale == other.scale;

  @override
  int get hashCode => Object.hash(pan, scale);
}
