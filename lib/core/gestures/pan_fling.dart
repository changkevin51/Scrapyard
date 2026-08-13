import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Decaying 2D pan after the finger lifts, matching Flutter's InteractiveViewer.
class PanFling {
  PanFling({
    required TickerProvider vsync,
    required this.onPanDelta,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  /// Finger-space delta, same sign as [PointerMoveEvent.delta].
  final void Function(Offset delta) onPanDelta;

  late final Ticker _ticker;
  FrictionSimulation? _simX;
  FrictionSimulation? _simY;
  double _lastX = 0;
  double _lastY = 0;

  /// Same drag as [InteractiveViewer.interactionEndFrictionCoefficient].
  static const double _drag = 0.0000135;

  bool get isActive => _ticker.isActive;

  void stop() {
    if (_ticker.isActive) _ticker.stop();
    _simX = null;
    _simY = null;
  }

  void start(Offset velocityPixelsPerSecond) {
    stop();
    if (velocityPixelsPerSecond.distance < kMinFlingVelocity) return;

    _simX = FrictionSimulation(_drag, 0, velocityPixelsPerSecond.dx);
    _simY = FrictionSimulation(_drag, 0, velocityPixelsPerSecond.dy);
    _lastX = 0;
    _lastY = 0;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final simX = _simX;
    final simY = _simY;
    if (simX == null || simY == null) {
      stop();
      return;
    }

    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final x = simX.x(t);
    final y = simY.x(t);
    final delta = Offset(x - _lastX, y - _lastY);
    _lastX = x;
    _lastY = y;

    if (simX.isDone(t) && simY.isDone(t)) {
      if (delta.distance > 0.01) onPanDelta(delta);
      stop();
      return;
    }

    if (delta.distance > 0.01) onPanDelta(delta);
  }

  void dispose() {
    _ticker.dispose();
  }
}
