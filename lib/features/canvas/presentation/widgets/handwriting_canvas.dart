import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../data/ink_renderer.dart';
import '../../data/pen_engine.dart';
import '../../data/smart_shape_recognizer.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../domain/models/stroke.dart';
import '../providers/canvas_providers.dart';

// ══════════════════════════════════════════════════════════════════
// Saved-stroke picture cache
// Lives in the State so it survives across CustomPainter rebuilds.
// ══════════════════════════════════════════════════════════════════
class _StrokeCache {
  ui.Picture? picture;
  List<Stroke>? _strokes;
  Size _size = Size.zero;
  PageLayout? _layout;

  bool isValid(List<Stroke> s, Size sz, PageLayout l) =>
      identical(_strokes, s) && sz == _size && l == _layout;

  void build(
    List<Stroke> strokes,
    Size size,
    PageLayout layout,
    void Function(Canvas, Size) drawFn,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    drawFn(canvas, size);
    picture = recorder.endRecording();
    _strokes = strokes;
    _size = size;
    _layout = layout;
  }

  void invalidate() {
    picture = null;
    _strokes = null;
  }
}

// ══════════════════════════════════════════════════════════════════
// HandwritingCanvas
// ══════════════════════════════════════════════════════════════════
class HandwritingCanvas extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final ScrollController horizontalScrollController;
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;
  final bool suppressTouchScroll;

  const HandwritingCanvas({
    super.key,
    required this.scrollController,
    required this.horizontalScrollController,
    required this.zoomLevel,
    required this.onZoomChanged,
    this.suppressTouchScroll = false,
  });

  @override
  ConsumerState<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends ConsumerState<HandwritingCanvas> {
  // Live stroke data — the painters hold a reference to this map directly.
  final _activeStrokes = <int, List<StrokePoint>>{};

  // Tracks which active pointers are highlighter strokes.
  final _activeIsHighlighter = <int, bool>{};
  final _activePenStyle = <int, PenStyle>{};
  final _activeColor = <int, Color>{};
  final _activeWidth = <int, double>{};

  // ValueNotifier drives live painters without widget rebuild.
  final _repaintTick = ValueNotifier<int>(0);

  // Separate picture caches so highlighter commits don't invalidate ink.
  final _hlCache = _StrokeCache();
  final _inkCache = _StrokeCache();

  // Cached bounds per stroke id for fast eraser / cluster hit-tests.
  final _boundsCache = <String, Rect>{};

  // Touch tracking for palm-rejection scroll/zoom
  final _touchPointers = <int, Offset>{};
  double? _pinchInitialDistance;
  double? _pinchInitialZoom;
  /// Canvas-local point under the pinch midpoint when the gesture began.
  Offset? _pinchContentFocal;
  bool _pinchScrollScheduled = false;
  double? _pendingHScroll;
  double? _pendingVScroll;

  // Hold-and-pause shape snap
  final _pauseTimers = <int, Timer>{};
  final _liveSnap = <int, ({ShapeType type, List<double> vertices})>{};

  final _uuid = const Uuid();
  final _shapeRecognizer = SmartShapeRecognizer();

  List<Stroke>? _lastStrokesRef;
  double? _lastStreamline;
  Map<PenStyle, double>? _lastSensitivity;

  void _tick() => _repaintTick.value++;

  // ── Input handlers ─────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent e) {
    final isPenMode = ref.read(isPenModeActiveProvider);
    final stylusOnly = ref.read(stylusOnlyModeProvider);

    if (e.kind == PointerDeviceKind.touch) {
      if (!isPenMode || stylusOnly) {
        _touchPointers[e.pointer] = e.position;
        if (_touchPointers.length == 2) {
          final positions = _touchPointers.values.toList();
          final distance = (positions[0] - positions[1]).distance;
          if (distance > 5.0) {
            _pinchInitialDistance = distance;
            _pinchInitialZoom = widget.zoomLevel;
            _pinchContentFocal = _canvasPointUnderPinch(positions);
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
    if (tool == CanvasTool.lasso || tool == CanvasTool.smelt) return;
    if (tool == CanvasTool.eraser) {
      _eraseAt(e.localPosition);
      return;
    }

    final settings = ref.read(penSettingsProvider);
    final color = ref.read(canvasColorProvider);
    final mod = ref.read(strokeWidthModifierProvider);

    final isHL = tool == CanvasTool.highlighter;
    double bWidth = 1.5 * mod;
    if (tool == CanvasTool.brush) bWidth = 3.0 * mod;
    if (isHL) bWidth = 12.0 * mod;
    if (tool == CanvasTool.tape) bWidth = 18.0 * mod;

    PenStyle style;
    if (isHL) {
      style = PenStyle.pen;
    } else if (tool == CanvasTool.brush) {
      // Brush tool uses the brush-family style from settings (or calligraphy).
      final s = settings.penStyle;
      style = s.family == InkFamily.brush ? s : PenStyle.calligraphy;
    } else if (tool == CanvasTool.pen) {
      final s = settings.penStyle;
      style = s.family == InkFamily.pen ? s : PenStyle.pen;
    } else {
      style = PenStyle.pen;
    }

    final effectiveColor =
        tool == CanvasTool.pen ? settings.effectiveColor(color) : color;

    _activeIsHighlighter[e.pointer] = isHL;
    _activePenStyle[e.pointer] = style;
    _activeColor[e.pointer] = effectiveColor;
    _activeWidth[e.pointer] = bWidth;
    _activeStrokes[e.pointer] = [_makePoint(e)];
    _liveSnap.remove(e.pointer);
    _armPauseTimer(e.pointer);
    _tick();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.touch &&
        _touchPointers.containsKey(e.pointer)) {
      _handleTouchMove(e);
      return;
    }

    final stylusOnly = ref.read(stylusOnlyModeProvider);
    if (stylusOnly &&
        e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    final tool = ref.read(activeCanvasToolProvider);
    final points = _activeStrokes[e.pointer];
    if (points == null) return;

    if (tool == CanvasTool.lasso || tool == CanvasTool.smelt) return;
    if (tool == CanvasTool.eraser) {
      _eraseAt(e.localPosition);
      return;
    }

    if (tool == CanvasTool.straightLine) {
      final pt = _makePoint(e);
      if (points.length > 1) {
        points[1] = pt;
      } else {
        points.add(pt);
      }
      _tick();
      return;
    }

    // Clear any live snap preview when the user continues drawing.
    _liveSnap.remove(e.pointer);

    points.add(_makePoint(e));
    _armPauseTimer(e.pointer);
    _tick();
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_touchPointers.remove(e.pointer) != null) {
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
        _pinchContentFocal = null;
      }
      return;
    }

    _cancelPauseTimer(e.pointer);
    final points = _activeStrokes.remove(e.pointer);
    final isHL = _activeIsHighlighter.remove(e.pointer) ?? false;
    final style = _activePenStyle.remove(e.pointer) ?? PenStyle.pen;
    final color = _activeColor.remove(e.pointer) ?? ScrapTheme.primaryText;
    final bWidth = _activeWidth.remove(e.pointer) ?? 1.5;
    final snap = _liveSnap.remove(e.pointer);

    if (points == null || points.isEmpty) {
      _tick();
      return;
    }

    final tool = ref.read(activeCanvasToolProvider);
    final strokeStyle = ref.read(strokeStyleProvider);
    final settings = ref.read(penSettingsProvider);

    if (tool == CanvasTool.lasso || tool == CanvasTool.smelt) {
      _tick();
      return;
    }

    // Text tool: short tap creates a text node (handled by note_editor).
    if (tool == CanvasTool.text) {
      final dx = points.last.x - points.first.x;
      final dy = points.last.y - points.first.y;
      if (dx * dx + dy * dy < 100) {
        _tick();
        return;
      }
    }

    ShapeType shapeType = ShapeType.none;
    List<double> vertices = [];

    final libraryShape = ref.read(selectedLibraryShapeProvider);
    if (tool == CanvasTool.shape && libraryShape != null) {
      shapeType = libraryShape;
      final cx =
          points.map((p) => p.x).reduce((a, b) => a + b) / points.length;
      final cy =
          points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
      vertices = _libraryVertices(libraryShape, cx, cy);
    } else if (tool == CanvasTool.shape) {
      final r = _shapeRecognizer.recognize(points);
      if (r.recognized) {
        shapeType = r.type;
        vertices = r.vertices;
      }
    } else if (snap != null) {
      // Hold-and-pause snap applied during the gesture.
      shapeType = snap.type;
      vertices = snap.vertices;
    }

    if (tool == CanvasTool.straightLine) {
      shapeType = ShapeType.line;
      vertices = [
        points.first.x,
        points.first.y,
        points.last.x,
        points.last.y,
      ];
    }

    final stroke = Stroke(
      id: _uuid.v4(),
      points: points,
      color: color,
      baseWidth: bWidth,
      isBrush: tool == CanvasTool.brush,
      isHighlighter: isHL,
      isTape: tool == CanvasTool.tape,
      isStraightLine: tool == CanvasTool.straightLine,
      style: strokeStyle,
      shapeType: shapeType,
      shapeVertices: vertices,
      isBeautified: settings.beautify &&
          (tool == CanvasTool.pen || tool == CanvasTool.brush),
      penStyle: style,
    );

    _boundsCache[stroke.id] =
        InkRenderer.boundsOf(points, pad: bWidth);
    if (isHL) {
      _hlCache.invalidate();
    } else {
      _inkCache.invalidate();
    }
    ref.read(strokesProvider.notifier).addStroke(stroke);
    _tick();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_touchPointers.remove(e.pointer) != null) {
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
        _pinchContentFocal = null;
      }
    }
    _cancelPauseTimer(e.pointer);
    _activeStrokes.remove(e.pointer);
    _activeIsHighlighter.remove(e.pointer);
    _activePenStyle.remove(e.pointer);
    _activeColor.remove(e.pointer);
    _activeWidth.remove(e.pointer);
    _liveSnap.remove(e.pointer);
    _tick();
  }

  // ── Hold-and-pause shape snap ──────────────────────────────────
  void _armPauseTimer(int pointer) {
    _cancelPauseTimer(pointer);
    final settings = ref.read(penSettingsProvider);
    final tool = ref.read(activeCanvasToolProvider);
    if (!settings.beautify) return;
    if (tool != CanvasTool.pen && tool != CanvasTool.brush) return;

    _pauseTimers[pointer] = Timer(const Duration(milliseconds: 350), () {
      final pts = _activeStrokes[pointer];
      if (pts == null || pts.length < 8) return;
      final r = _shapeRecognizer.recognize(pts);
      if (r.recognized) {
        _liveSnap[pointer] = (type: r.type, vertices: r.vertices);
        _tick();
      }
    });
  }

  void _cancelPauseTimer(int pointer) {
    _pauseTimers.remove(pointer)?.cancel();
  }

  // ── Helpers ────────────────────────────────────────────────────
  List<double> _libraryVertices(ShapeType type, double cx, double cy) {
    const r = 60.0;
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

  List<double> _starVertices(
      double cx, double cy, double outerR, double innerR) {
    final verts = <double>[];
    const points5 = 5;
    for (int i = 0; i < points5 * 2; i++) {
      final angle = (i * pi / points5) - pi / 2;
      final r = i.isEven ? outerR : innerR;
      verts.addAll([cx + r * cos(angle), cy + r * sin(angle)]);
    }
    return verts;
  }

  /// Left inset of the scaled page inside the horizontal scroll content
  /// (centers the sheet when zoomed out past the viewport width).
  double _contentOriginX(double viewportW, double zoom) {
    final scaledW = viewportW * zoom;
    return scaledW < viewportW ? (viewportW - scaledW) / 2.0 : 0.0;
  }

  RenderBox? _scrollViewportBox() {
    if (!widget.scrollController.hasClients) return null;
    return widget.scrollController.position.context.storageContext
        .findRenderObject() as RenderBox?;
  }

  /// Canvas-local point currently under the pinch midpoint.
  Offset? _canvasPointUnderPinch(List<Offset> globalPositions) {
    final box = _scrollViewportBox();
    if (box == null || !box.hasSize) return null;

    final mid = Offset(
      (globalPositions[0].dx + globalPositions[1].dx) / 2,
      (globalPositions[0].dy + globalPositions[1].dy) / 2,
    );
    final focalVp = box.globalToLocal(mid);
    final zoom = widget.zoomLevel;
    if (zoom <= 0) return null;

    final originX = _contentOriginX(box.size.width, zoom);
    final h = widget.horizontalScrollController.hasClients
        ? widget.horizontalScrollController.offset
        : 0.0;
    final v = widget.scrollController.offset;
    return Offset(
      (focalVp.dx + h - originX) / zoom,
      (focalVp.dy + v) / zoom,
    );
  }

  void _scheduleScrollTo(double h, double v) {
    _pendingHScroll = h;
    _pendingVScroll = v;
    if (_pinchScrollScheduled) return;
    _pinchScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinchScrollScheduled = false;
      if (!mounted) return;
      final targetH = _pendingHScroll;
      final targetV = _pendingVScroll;
      if (targetH == null || targetV == null) return;

      final vScroll = widget.scrollController;
      if (vScroll.hasClients) {
        vScroll.jumpTo(
          targetV.clamp(0.0, vScroll.position.maxScrollExtent),
        );
      }
      final hScroll = widget.horizontalScrollController;
      if (hScroll.hasClients) {
        hScroll.jumpTo(
          targetH.clamp(0.0, hScroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _handleTouchMove(PointerMoveEvent e) {
    final previous = _touchPointers[e.pointer];
    _touchPointers[e.pointer] = e.position;

    if (_touchPointers.length == 2 &&
        _pinchInitialDistance != null &&
        _pinchInitialZoom != null &&
        _pinchContentFocal != null) {
      final positions = _touchPointers.values.toList();
      final currentDistance = (positions[0] - positions[1]).distance;
      if (currentDistance <= 5.0) return;

      final box = _scrollViewportBox();
      if (box == null || !box.hasSize) {
        final newZoom =
            (_pinchInitialZoom! * (currentDistance / _pinchInitialDistance!))
                .clamp(0.5, 3.0);
        widget.onZoomChanged(newZoom);
        return;
      }

      final newZoom =
          (_pinchInitialZoom! * (currentDistance / _pinchInitialDistance!))
              .clamp(0.5, 3.0);
      final mid = Offset(
        (positions[0].dx + positions[1].dx) / 2,
        (positions[0].dy + positions[1].dy) / 2,
      );
      final focalVp = box.globalToLocal(mid);
      final originX = _contentOriginX(box.size.width, newZoom);
      final focal = _pinchContentFocal!;

      // Keep the original canvas point under the live pinch midpoint.
      final newH = focal.dx * newZoom + originX - focalVp.dx;
      final newV = focal.dy * newZoom - focalVp.dy;

      widget.onZoomChanged(newZoom);
      _scheduleScrollTo(newH, newV);
    } else if (previous != null &&
        !widget.suppressTouchScroll &&
        widget.scrollController.hasClients) {
      if (ref.read(isPenModeActiveProvider)) {
        final delta = e.position - previous;
        final vScroll = widget.scrollController;
        vScroll.jumpTo(
          (vScroll.offset - delta.dy)
              .clamp(0.0, vScroll.position.maxScrollExtent),
        );
        final hScroll = widget.horizontalScrollController;
        if (hScroll.hasClients) {
          hScroll.jumpTo(
            (hScroll.offset - delta.dx)
                .clamp(0.0, hScroll.position.maxScrollExtent),
          );
        }
      }
    }
  }

  void _eraseAt(Offset pos) {
    final strokes = ref.read(strokesProvider);
    final toHide = <String>[];
    for (final s in strokes) {
      if (s.isHidden) continue;
      final bounds = _boundsCache.putIfAbsent(
        s.id,
        () => InkRenderer.boundsOf(s.points, pad: 20),
      );
      if (!bounds.inflate(20).contains(pos)) continue;
      if (_strokeNearPoint(s, pos)) toHide.add(s.id);
    }
    if (toHide.isNotEmpty) {
      _hlCache.invalidate();
      _inkCache.invalidate();
      for (final id in toHide) {
        _boundsCache.remove(id);
      }
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
        x: e.localPosition.dx,
        y: e.localPosition.dy,
        pressure: e.pressure > 0 ? e.pressure : 1.0,
        timestamp: e.timeStamp.inMicroseconds,
      );

  @override
  void dispose() {
    for (final t in _pauseTimers.values) {
      t.cancel();
    }
    _repaintTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes = ref.watch(strokesProvider);
    final pageLayout = ref.watch(pageLayoutProvider);
    final penSettings = ref.watch(penSettingsProvider);

    // Invalidate caches only when the stroke list identity changes.
    if (!identical(_lastStrokesRef, strokes)) {
      _lastStrokesRef = strokes;
      _hlCache.invalidate();
      _inkCache.invalidate();
      for (final s in strokes) {
        _boundsCache.putIfAbsent(
          s.id,
          () => InkRenderer.boundsOf(s.points, pad: s.baseWidth),
        );
      }
    }

    // Streamline / sensitivity affect ink rasterization — rebuild ink picture.
    if (_lastStreamline != penSettings.streamline ||
        !identical(_lastSensitivity, penSettings.sensitivity)) {
      _lastStreamline = penSettings.streamline;
      _lastSensitivity = penSettings.sensitivity;
      _inkCache.invalidate();
    }

    final hlStrokes =
        strokes.where((s) => !s.isHidden && s.isHighlighter).toList();
    final inkStrokes =
        strokes.where((s) => !s.isHidden && !s.isHighlighter).toList();

    return RepaintBoundary(
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: background + committed highlighters
            CustomPaint(
              painter: _HighlightLayerPainter(
                strokes: hlStrokes,
                pageLayout: pageLayout,
                cache: _hlCache,
                allStrokes: strokes,
              ),
              size: Size.infinite,
            ),
            // Layer 2: live highlighter
            RepaintBoundary(
              child: CustomPaint(
                painter: _LiveStrokePainter(
                  activeStrokes: _activeStrokes,
                  activeIsHighlighter: _activeIsHighlighter,
                  activePenStyle: _activePenStyle,
                  activeColor: _activeColor,
                  activeWidth: _activeWidth,
                  liveSnap: _liveSnap,
                  highlighterOnly: true,
                  streamline: penSettings.streamline,
                  sensitivity: penSettings.sensitivityFor(penSettings.penStyle),
                  repaint: _repaintTick,
                ),
                size: Size.infinite,
              ),
            ),
            // Layer 3: committed pen/brush ink
            CustomPaint(
              painter: _InkLayerPainter(
                strokes: inkStrokes,
                cache: _inkCache,
                allStrokes: strokes,
                streamline: penSettings.streamline,
                sensitivityMap: penSettings.sensitivity,
              ),
              size: Size.infinite,
            ),
            // Layer 4: live pen/brush
            RepaintBoundary(
              child: CustomPaint(
                painter: _LiveStrokePainter(
                  activeStrokes: _activeStrokes,
                  activeIsHighlighter: _activeIsHighlighter,
                  activePenStyle: _activePenStyle,
                  activeColor: _activeColor,
                  activeWidth: _activeWidth,
                  liveSnap: _liveSnap,
                  highlighterOnly: false,
                  streamline: penSettings.streamline,
                  sensitivity: penSettings.sensitivityFor(penSettings.penStyle),
                  repaint: _repaintTick,
                ),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Layer 1 — background + committed highlighters
// ══════════════════════════════════════════════════════════════════
class _HighlightLayerPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Stroke> allStrokes;
  final PageLayout pageLayout;
  final _StrokeCache cache;

  _HighlightLayerPainter({
    required this.strokes,
    required this.allStrokes,
    required this.pageLayout,
    required this.cache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!cache.isValid(allStrokes, size, pageLayout)) {
      cache.build(allStrokes, size, pageLayout, (c, sz) {
        c.drawColor(ScrapTheme.background, BlendMode.srcOver);
        _drawPageLines(c, sz, pageLayout);
        for (final stroke in strokes) {
          InkRenderer.paintStroke(c, stroke);
        }
      });
    }
    canvas.drawPicture(cache.picture!);
  }

  @override
  bool shouldRepaint(covariant _HighlightLayerPainter old) =>
      old.pageLayout != pageLayout || !identical(old.allStrokes, allStrokes);
}

// ══════════════════════════════════════════════════════════════════
// Layer 3 — committed ink (non-highlighter)
// ══════════════════════════════════════════════════════════════════
class _InkLayerPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Stroke> allStrokes;
  final _StrokeCache cache;
  final double streamline;
  final Map<PenStyle, double> sensitivityMap;

  _InkLayerPainter({
    required this.strokes,
    required this.allStrokes,
    required this.cache,
    required this.streamline,
    required this.sensitivityMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Use a blank PageLayout sentinel — ink cache only cares about stroke list.
    if (!cache.isValid(allStrokes, size, PageLayout.plain)) {
      cache.build(allStrokes, size, PageLayout.plain, (c, sz) {
        for (final stroke in strokes) {
          if (stroke.shapeType != ShapeType.none &&
              stroke.shapeVertices.isNotEmpty) {
            _paintShape(c, stroke);
          } else {
            InkRenderer.paint(
              canvas: c,
              pts: stroke.points,
              color: stroke.color,
              baseWidth: stroke.baseWidth,
              style: stroke.penStyle,
              isHighlighter: false,
              streamline: streamline,
              sensitivity:
                  sensitivityMap[stroke.penStyle] ?? 0.5,
            );
          }
        }
      });
    }
    canvas.drawPicture(cache.picture!);
  }

  @override
  bool shouldRepaint(covariant _InkLayerPainter old) =>
      !identical(old.allStrokes, allStrokes) ||
      old.streamline != streamline;
}

// ══════════════════════════════════════════════════════════════════
// Layers 2 & 4 — live in-progress strokes
// ══════════════════════════════════════════════════════════════════
class _LiveStrokePainter extends CustomPainter {
  final Map<int, List<StrokePoint>> activeStrokes;
  final Map<int, bool> activeIsHighlighter;
  final Map<int, PenStyle> activePenStyle;
  final Map<int, Color> activeColor;
  final Map<int, double> activeWidth;
  final Map<int, ({ShapeType type, List<double> vertices})> liveSnap;
  final bool highlighterOnly;
  final double streamline;
  final double sensitivity;

  _LiveStrokePainter({
    required this.activeStrokes,
    required this.activeIsHighlighter,
    required this.activePenStyle,
    required this.activeColor,
    required this.activeWidth,
    required this.liveSnap,
    required this.highlighterOnly,
    required this.streamline,
    required this.sensitivity,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in activeStrokes.entries) {
      final id = entry.key;
      final pts = entry.value;
      if (pts.isEmpty) continue;

      final isHL = activeIsHighlighter[id] ?? false;
      if (highlighterOnly != isHL) continue;

      // Live shape snap preview
      final snap = liveSnap[id];
      if (snap != null) {
        _paintShapePreview(
          canvas,
          snap.type,
          snap.vertices,
          activeColor[id] ?? ScrapTheme.primaryText,
          activeWidth[id] ?? 1.5,
        );
        continue;
      }

      InkRenderer.paint(
        canvas: canvas,
        pts: pts,
        color: activeColor[id] ?? ScrapTheme.primaryText,
        baseWidth: activeWidth[id] ?? 1.5,
        style: activePenStyle[id] ?? PenStyle.pen,
        isHighlighter: isHL,
        streamline: streamline,
        sensitivity: sensitivity,
        isComplete: false,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveStrokePainter old) => true;
}

// ── Shared helpers ───────────────────────────────────────────────

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

void _paintShapePreview(
  Canvas canvas,
  ShapeType type,
  List<double> v,
  Color color,
  double width,
) {
  _paintShape(
    canvas,
    Stroke(
      id: '',
      points: const [],
      color: color.withValues(alpha: 0.7),
      baseWidth: width,
      shapeType: type,
      shapeVertices: v,
    ),
  );
}

void _drawPageLines(Canvas canvas, Size size, PageLayout pageLayout) {
  final p = Paint()
    ..color = ScrapTheme.notebookLines
    ..strokeWidth = 0.7;
  if (pageLayout == PageLayout.ruled) {
    final headerPaint = Paint()
      ..color = ScrapTheme.notebookLines
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(0, 34), Offset(size.width, 34), headerPaint);
    canvas.drawLine(const Offset(0, 38), Offset(size.width, 38), headerPaint);
    for (double y = 72; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    final marginPaint = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        const Offset(56, 0), Offset(56, size.height), marginPaint);
  } else if (pageLayout == PageLayout.grid) {
    for (double y = 36; y < size.height; y += 36) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (double x = 36; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    final marginPaint = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    canvas.drawLine(
        const Offset(56, 0), Offset(56, size.height), marginPaint);
  } else if (pageLayout == PageLayout.dotted) {
    final dp = Paint()
      ..color = ScrapTheme.notebookLines
      ..style = PaintingStyle.fill;
    for (double y = 36; y < size.height; y += 36) {
      for (double x = 36; x < size.width; x += 36) {
        canvas.drawCircle(Offset(x, y), 1.5, dp);
      }
    }
  }

  _drawPageEdge(canvas, size);
}

void _drawPageEdge(Canvas canvas, Size size) {
  const inset = 2.0;
  final edgePaint = Paint()
    ..color = ScrapTheme.dividers
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;
  canvas.drawRect(
    Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2),
    edgePaint,
  );

  final rightGrad = Paint()
    ..shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        ScrapTheme.kraft.withValues(alpha: 0.0),
        ScrapTheme.kraft.withValues(alpha: 0.12),
      ],
    ).createShader(Rect.fromLTWH(size.width - 6, 0, 6, size.height));
  canvas.drawRect(Rect.fromLTWH(size.width - 6, 0, 6, size.height), rightGrad);

  final bottomGrad = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        ScrapTheme.kraft.withValues(alpha: 0.0),
        ScrapTheme.kraft.withValues(alpha: 0.12),
      ],
    ).createShader(Rect.fromLTWH(0, size.height - 6, size.width, 6));
  canvas.drawRect(Rect.fromLTWH(0, size.height - 6, size.width, 6), bottomGrad);
}
