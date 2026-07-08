import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/stroke.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../data/smart_shape_recognizer.dart';
import '../../data/pen_engine.dart';
import '../providers/canvas_providers.dart';
import 'package:uuid/uuid.dart';

// ══════════════════════════════════════════════════════════════════
// Saved-stroke picture cache
// Lives in the State so it survives across CustomPainter rebuilds.
// ══════════════════════════════════════════════════════════════════
class _StrokeCache {
  ui.Picture? picture;
  List<Stroke>? _strokes;
  Size         _size      = Size.zero;
  PageLayout?  _layout;
  bool?        _beautify;

  bool isValid(List<Stroke> s, Size sz, PageLayout l, bool b) =>
      identical(_strokes, s) && sz == _size && l == _layout && b == _beautify;

  void build(
    List<Stroke> strokes,
    Size size,
    PageLayout layout,
    bool beautify,
    void Function(Canvas, Size) drawFn,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    drawFn(canvas, size);
    picture   = recorder.endRecording();
    _strokes  = strokes;
    _size     = size;
    _layout   = layout;
    _beautify = beautify;
  }

  void invalidate() { picture = null; _strokes = null; }
}

// ══════════════════════════════════════════════════════════════════
// HandwritingCanvas
// ══════════════════════════════════════════════════════════════════
class HandwritingCanvas extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;

  const HandwritingCanvas({
    super.key,
    required this.scrollController,
    required this.zoomLevel,
    required this.onZoomChanged,
  });

  @override
  ConsumerState<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends ConsumerState<HandwritingCanvas> {
  // Live stroke data — the painter holds a reference to this map directly.
  // No copy is made; this is intentional and safe in Flutter's single-threaded model.
  final _activeStrokes = <int, List<StrokePoint>>{};
  final _stabilizers   = <int, StrokeStabilizer>{};

  // ValueNotifier drives CustomPainter.markNeedsPaint() directly —
  // bypasses widget rebuild + layout phase entirely.
  // This is the key to zero-lag drawing at 120 Hz.
  final _repaintTick = ValueNotifier<int>(0);

  // Saved-stroke picture cache — rebuilt only when the stroke list changes.
  final _cache = _StrokeCache();

  // Touch tracking for palm-rejection scroll/zoom
  final _touchPointers = <int, Offset>{};
  double? _pinchInitialDistance;
  double? _pinchInitialZoom;

  final _uuid            = const Uuid();
  final _shapeRecognizer = SmartShapeRecognizer();

  void _tick() => _repaintTick.value++;

  // ── Input handlers ─────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent e) {
    final isPenMode = ref.read(isPenModeActiveProvider);
    final stylusOnly = ref.read(stylusOnlyModeProvider);

    // Track touch for zoom/scroll in touch mode or palm-rejection mode.
    // In pen mode without palm-rejection, touch events draw — don't track.
    if (e.kind == PointerDeviceKind.touch) {
      if (!isPenMode || stylusOnly) {
        _touchPointers[e.pointer] = e.position;
        if (_touchPointers.length == 2) {
          final positions = _touchPointers.values.toList();
          final distance = (positions[0] - positions[1]).distance;
          if (distance > 5.0) {
            _pinchInitialDistance = distance;
            _pinchInitialZoom = widget.zoomLevel;
          }
        }
      }
    }

    if (!isPenMode) return;

    if (stylusOnly &&
        e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    final tool = ref.read(activeCanvasToolProvider);
    if (tool == CanvasTool.lasso) return;
    if (tool == CanvasTool.eraser) { _eraseAt(e.localPosition); return; }

    final stab = StrokeStabilizer()..start(e.localPosition);
    _stabilizers[e.pointer]   = stab;
    _activeStrokes[e.pointer] = [
      StrokePoint(
        x: e.localPosition.dx, y: e.localPosition.dy,
        pressure: e.pressure > 0 ? e.pressure : 1.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      )
    ];
    _tick();
  }

  void _onPointerMove(PointerMoveEvent e) {
    // Tracked touch moves — handled for zoom/scroll in any mode
    if (e.kind == PointerDeviceKind.touch && _touchPointers.containsKey(e.pointer)) {
      _handleTouchMove(e);
      return;
    }

    final stylusOnly = ref.read(stylusOnlyModeProvider);
    if (stylusOnly &&
        e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    final tool   = ref.read(activeCanvasToolProvider);
    final points = _activeStrokes[e.pointer];
    if (points == null) return;

    if (tool == CanvasTool.lasso) return;

    if (tool == CanvasTool.eraser) { _eraseAt(e.localPosition); return; }

    if (tool == CanvasTool.straightLine) {
      final pt = _makePoint(e);
      if (points.length > 1) { points[1] = pt; } else { points.add(pt); }
      _tick();
      return;
    }

    final settings = ref.read(penSettingsProvider);
    final stab     = _stabilizers[e.pointer];
    final raw      = e.localPosition;

    final stabilized = (tool == CanvasTool.pen && stab != null)
        ? stab.process(raw, settings.stability)
        : raw;

    if (stabilized == null) return; // rope still taut

    points.add(StrokePoint(
      x: stabilized.dx, y: stabilized.dy,
      pressure: e.pressure > 0 ? e.pressure : 1.0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    _tick(); // NO setState — direct paint signal
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_touchPointers.remove(e.pointer) != null) {
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
      }
      return;
    }
    _stabilizers.remove(e.pointer)?.reset();
    final points = _activeStrokes.remove(e.pointer);
    if (points == null || points.length < 2) { _tick(); return; }

    final color    = ref.read(canvasColorProvider);
    final tool     = ref.read(activeCanvasToolProvider);
    final style    = ref.read(strokeStyleProvider);
    final mod      = ref.read(strokeWidthModifierProvider);
    final settings = ref.read(penSettingsProvider);

    if (tool == CanvasTool.lasso) {
      _tick();
      return;
    }

    // If text tool and SHORT tap (not a drag) — let note_editor create text node, skip stroke
    if (tool == CanvasTool.text) {
      final dx = points.last.x - points.first.x;
      final dy = points.last.y - points.first.y;
      if (dx * dx + dy * dy < 100) { _tick(); return; } // < 10px movement = tap
    }

    final effectiveColor = tool == CanvasTool.pen
        ? settings.effectiveColor(color)
        : color;

    double bWidth = 1.5 * mod;
    if (tool == CanvasTool.brush)       bWidth = 3.0  * mod;
    if (tool == CanvasTool.highlighter) bWidth = 12.0 * mod;
    if (tool == CanvasTool.tape)        bWidth = 18.0 * mod;

    ShapeType shapeType   = ShapeType.none;
    List<double> vertices = [];

    // Shape library: place pre-defined shape at tap position
    final libraryShape = ref.read(selectedLibraryShapeProvider);
    if (tool == CanvasTool.shape && libraryShape != null) {
      shapeType = libraryShape;
      final cx  = points.map((p) => p.x).reduce((a, b) => a + b) / points.length;
      final cy  = points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
      vertices  = _libraryVertices(libraryShape, cx, cy);
    } else if (tool == CanvasTool.shape) {
      final r = _shapeRecognizer.recognize(points);
      if (r.recognized) { shapeType = r.type; vertices = r.vertices; }
    }
    if (tool == CanvasTool.straightLine) {
      shapeType = ShapeType.line;
      vertices  = [points.first.x, points.first.y, points.last.x, points.last.y];
    }

    _cache.invalidate();
    ref.read(strokesProvider.notifier).addStroke(Stroke(
      id: _uuid.v4(), points: points,
      color: effectiveColor, baseWidth: bWidth,
      isBrush: tool == CanvasTool.brush,
      isHighlighter: tool == CanvasTool.highlighter,
      isTape: tool == CanvasTool.tape,
      isStraightLine: tool == CanvasTool.straightLine,
      style: style, shapeType: shapeType, shapeVertices: vertices,
      // Bake both flags permanently into the stroke
      isBeautified: settings.beautify && (tool == CanvasTool.pen || tool == CanvasTool.brush),
      penStyle: (tool == CanvasTool.pen) ? settings.penStyle : PenStyle.normal,
    ));
    _tick();
  }

  /// Generate standard vertices for a library shape centered at (cx, cy)
  List<double> _libraryVertices(ShapeType type, double cx, double cy) {
    const r = 60.0; // default radius / half-size
    switch (type) {
      case ShapeType.circle:
      case ShapeType.oval:
        return [cx - r, cy - r, cx + r, cy + r];
      case ShapeType.square:
      case ShapeType.rectangle:
        return [cx - r, cy - r * 0.75, cx + r, cy + r * 0.75];
      case ShapeType.triangle:
        return [cx, cy - r, cx - r, cy + r, cx + r, cy + r];
      case ShapeType.diamond:
        return [cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy];
      case ShapeType.star:
        return _starVertices(cx, cy, r, r * 0.4);
      case ShapeType.line:
        return [cx - r, cy, cx + r, cy];
      case ShapeType.none:
        return [];
    }
  }

  List<double> _starVertices(double cx, double cy, double outerR, double innerR) {
    final verts = <double>[];
    const points5 = 5;
    for (int i = 0; i < points5 * 2; i++) {
      final angle = (i * 3.14159265 / points5) - 3.14159265 / 2;
      final r = i.isEven ? outerR : innerR;
      verts.addAll([cx + r * cos(angle), cy + r * sin(angle)]);
    }
    return verts;
  }

  void _handleTouchMove(PointerMoveEvent e) {
    final previous = _touchPointers[e.pointer];
    _touchPointers[e.pointer] = e.position;

    if (_touchPointers.length == 2 && _pinchInitialDistance != null && _pinchInitialZoom != null) {
      final positions = _touchPointers.values.toList();
      final currentDistance = (positions[0] - positions[1]).distance;
      if (currentDistance > 5.0) {
        final newZoom = _pinchInitialZoom! * (currentDistance / _pinchInitialDistance!);
        widget.onZoomChanged(newZoom.clamp(0.5, 3.0));
      }
    } else if (previous != null && widget.scrollController.hasClients) {
      // Only scroll manually in pen mode — in touch mode the
      // ScrollView's AlwaysScrollableScrollPhysics handles it.
      if (ref.read(isPenModeActiveProvider)) {
        final delta = e.position - previous;
        final maxExtent = widget.scrollController.position.maxScrollExtent;
        widget.scrollController.jumpTo(
          (widget.scrollController.offset - delta.dy).clamp(0.0, maxExtent),
        );
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_touchPointers.remove(e.pointer) != null) {
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
      }
    }
    _stabilizers.remove(e.pointer)?.reset();
    _activeStrokes.remove(e.pointer);
    _tick();
  }

  void _eraseAt(Offset pos) {
    final toHide = ref.read(strokesProvider)
        .where((s) => !s.isHidden && _strokeNearPoint(s, pos))
        .map((s) => s.id).toList();
    if (toHide.isNotEmpty) {
      _cache.invalidate();
      ref.read(strokesProvider.notifier).hideStrokes(toHide);
    }
  }

  bool _strokeNearPoint(Stroke s, Offset pos, {double radius = 20}) {
    for (final pt in s.points) {
      if ((Offset(pt.x, pt.y) - pos).distance < radius) return true;
    }
    return false;
  }

  StrokePoint _makePoint(PointerEvent e) => StrokePoint(
    x: e.localPosition.dx, y: e.localPosition.dy,
    pressure: e.pressure > 0 ? e.pressure : 1.0,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  @override
  void dispose() {
    _repaintTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes     = ref.watch(strokesProvider);
    final pageLayout  = ref.watch(pageLayoutProvider);
    final penSettings = ref.watch(penSettingsProvider);

    // When Riverpod strokes change, invalidate cache so it rebuilds
    _cache.invalidate();

    return RepaintBoundary(
      child: Listener(
        onPointerDown:   _onPointerDown,
        onPointerMove:   _onPointerMove,
        onPointerUp:     _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: CustomPaint(
          painter: CanvasPainter(
            strokes:         strokes,
            activeStrokes:   _activeStrokes,
            pageLayout:      pageLayout,
            beautify:        penSettings.beautify,
            predict:         penSettings.predict,
            currentPenStyle: penSettings.penStyle,
            cache:           _cache,
            repaint:         _repaintTick,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CanvasPainter
//
// Two-layer architecture:
//   Layer 1 (cached ui.Picture)  — page background + saved strokes
//   Layer 2 (raw, live)          — current in-progress stroke(s)
//
// Layer 1 is rebuilt only when the stroke list identity changes.
// Layer 2 is drawn every frame at native refresh rate via ValueNotifier.
// ══════════════════════════════════════════════════════════════════
class CanvasPainter extends CustomPainter {
  final List<Stroke>                strokes;
  final Map<int, List<StrokePoint>> activeStrokes; // live ref
  final PageLayout                  pageLayout;
  final bool                        beautify;
  final bool                        predict;
  final PenStyle                    currentPenStyle;
  final _StrokeCache                cache;

  CanvasPainter({
    required this.strokes,
    required this.activeStrokes,
    required this.pageLayout,
    required this.beautify,
    required this.predict,
    required this.currentPenStyle,
    required this.cache,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (!cache.isValid(strokes, size, pageLayout, beautify)) {
      cache.build(strokes, size, pageLayout, beautify, _buildSavedLayer);
    }
    canvas.drawPicture(cache.picture!);

    // Layer 2: active strokes — live style preview
    for (final pts in activeStrokes.values) {
      if (pts.isEmpty) continue;
      if (currentPenStyle == PenStyle.calligraphy ||
          currentPenStyle == PenStyle.fountain ||
          currentPenStyle == PenStyle.ballpoint) {
        StrokeRenderer.paintStyled(
          canvas: canvas, pts: pts,
          color: KotoTheme.primaryText, baseWidth: 1.5,
          style: currentPenStyle, isHighlighter: false,
        );
      } else {
        _paintRaw(canvas, pts, KotoTheme.primaryText, 1.5);
      }
      if (predict) _paintPrediction(canvas, pts);
    }
  }

  // Saved layer: each stroke rendered via its baked penStyle
  void _buildSavedLayer(Canvas canvas, Size size) {
    canvas.drawColor(KotoTheme.background, BlendMode.srcOver);
    _drawPageLines(canvas, size);
    for (final stroke in strokes) {
      if (stroke.isHidden) continue;
      if (stroke.shapeType != ShapeType.none && stroke.shapeVertices.isNotEmpty) {
        _paintShape(canvas, stroke);
      } else {
        StrokeRenderer.paintStyled(
          canvas: canvas, pts: stroke.points,
          color: stroke.color, baseWidth: stroke.baseWidth,
          style: stroke.penStyle, isHighlighter: stroke.isHighlighter,
        );
      }
    }
  }

  // ── Page rule/grid/dot backgrounds ───────────────────────────
  void _drawPageLines(Canvas canvas, Size size) {
    final p = Paint()..color = KotoTheme.notebookLines..strokeWidth = 0.7;
    if (pageLayout == PageLayout.ruled) {
      for (double y = 36; y < size.height; y += 36) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
    } else if (pageLayout == PageLayout.grid) {
      for (double y = 36; y < size.height; y += 36) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      }
      for (double x = 36; x < size.width; x += 36) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      }
    } else if (pageLayout == PageLayout.dotted) {
      final dp = Paint()..color = KotoTheme.notebookLines..style = PaintingStyle.fill;
      for (double y = 36; y < size.height; y += 36) {
        for (double x = 36; x < size.width; x += 36) {
          canvas.drawCircle(Offset(x, y), 1.5, dp);
        }
      }
    }
  }

  // ── Raw segment rendering (active stroke — max speed) ────────
  void _paintRaw(
    Canvas canvas,
    List<StrokePoint> pts,
    Color color,
    double baseWidth, {
    bool isHighlighter = false,
  }) {
    if (pts.length < 2) return;
    final paint = Paint()
      ..color = isHighlighter ? color.withValues(alpha: 0.30) : color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (isHighlighter) paint.blendMode = BlendMode.multiply;

    // Build a single path for the whole active stroke — one draw call
    final path = Path()..moveTo(pts.first.x, pts.first.y);
    for (int i = 1; i < pts.length; i++) {
      paint.strokeWidth = max(0.8, min(6.0, baseWidth + pts[i].pressure * baseWidth * 1.4));
      path.lineTo(pts[i].x, pts[i].y);
    }
    canvas.drawPath(path, paint);
  }

  // ── Handwriting prediction ghost ─────────────────────────────
  void _paintPrediction(Canvas canvas, List<StrokePoint> pts) {
    if (pts.length < 4) return;
    final n      = min(6, pts.length);
    final recent = pts.sublist(pts.length - n);
    var vx = 0.0, vy = 0.0, totalW = 0.0;
    for (int i = 1; i < recent.length; i++) {
      final w = i.toDouble();
      vx += (recent[i].x - recent[i-1].x) * w;
      vy += (recent[i].y - recent[i-1].y) * w;
      totalW += w;
    }
    if (totalW == 0 || sqrt(vx*vx+vy*vy) / totalW < 0.5) return;
    vx /= totalW; vy /= totalW;

    final last = Offset(pts.last.x, pts.last.y);
    final ghost = <Offset>[last];
    for (int i = 1; i <= 10; i++) {
      final d = 1.0 - (i / 12.0);
      ghost.add(last + Offset(vx * i * d, vy * i * d));
    }

    final p = Paint()
      ..color = KotoTheme.mutedText.withValues(alpha: 0.20)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    bool draw = true;
    for (int i = 1; i < ghost.length; i++) {
      if (draw) canvas.drawLine(ghost[i-1], ghost[i], p);
      draw = !draw;
    }
  }

  // ── Perfect geometric shapes ──────────────────────────────────
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
        if (v.length >= 4) canvas.drawLine(Offset(v[0],v[1]), Offset(v[2],v[3]), p);
        break;
      case ShapeType.circle:
      case ShapeType.oval:
        if (v.length >= 4) canvas.drawOval(Rect.fromLTRB(v[0],v[1],v[2],v[3]), p);
        break;
      case ShapeType.rectangle:
      case ShapeType.square:
        if (v.length >= 4) canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(v[0],v[1],v[2],v[3]), const Radius.circular(4)), p);
        break;
      case ShapeType.triangle:
        if (v.length >= 6) canvas.drawPath(
          Path()..moveTo(v[0],v[1])..lineTo(v[2],v[3])..lineTo(v[4],v[5])..close(), p);
        break;
      case ShapeType.diamond:
        if (v.length >= 8) canvas.drawPath(
          Path()..moveTo(v[0],v[1])..lineTo(v[2],v[3])
                ..lineTo(v[4],v[5])..lineTo(v[6],v[7])..close(), p);
        break;
      case ShapeType.star:
        if (v.length >= 10) {
          final path = Path()..moveTo(v[0], v[1]);
          for (int i = 2; i < v.length; i += 2) path.lineTo(v[i], v[i+1]);
          path.close();
          canvas.drawPath(path, p);
        }
        break;
      case ShapeType.none:
        break;
    }
  }

  // Avoid full rebuild on every Riverpod refresh — only rebuild
  // when data that affects the saved-stroke layer changes.
  @override
  bool shouldRepaint(covariant CanvasPainter old) =>
      old.beautify   != beautify   ||
      old.predict    != predict    ||
      old.pageLayout != pageLayout ||
      !identical(old.strokes, strokes);
}
