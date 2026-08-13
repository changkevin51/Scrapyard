import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/gestures/pan_fling.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../gestures/presentation/providers/gesture_providers.dart';
import '../../data/ink_renderer.dart';
import '../../data/pen_engine.dart';
import '../../data/smart_shape_recognizer.dart';
import '../../data/stroke_sampler.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../domain/models/canvas_viewport.dart';
import '../../domain/models/stroke.dart';
import '../../domain/services/stroke_spatial_index.dart';
import '../providers/canvas_providers.dart';
import '../providers/canvas_viewport_provider.dart';
import 'eraser_preview.dart';

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

/// World-space overscan picture cache for infinite canvas.
/// Rebuilds when the stroke list changes, LOD tier changes, or the visible
/// world leaves the buffered rect.
class _InfinitePictureCache {
  ui.Picture? picture;
  List<Stroke>? _strokes;
  Rect? bufferedWorld;
  int? lodTier;

  static int lodTierFor(double scale) {
    if (scale < 0.15) return 0;
    if (scale < 0.3) return 1;
    return 2;
  }

  bool isValid(List<Stroke> s, Rect visible, double scale) {
    if (picture == null ||
        bufferedWorld == null ||
        !identical(_strokes, s) ||
        lodTier != lodTierFor(scale)) {
      return false;
    }
    // Keep a small inner margin so we rebuild before the edge is visible.
    final margin = bufferedWorld!.width * 0.05;
    final inner = bufferedWorld!.deflate(margin);
    return inner.contains(visible.topLeft) &&
        inner.contains(visible.bottomRight);
  }

  void build(
    List<Stroke> strokes,
    Rect buffer,
    double scale,
    void Function(Canvas canvas, Rect buffer) drawFn,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, buffer.width, buffer.height),
    );
    // Draw in world coords relative to buffer origin for a compact picture.
    canvas.translate(-buffer.left, -buffer.top);
    drawFn(canvas, buffer);
    picture = recorder.endRecording();
    _strokes = strokes;
    bufferedWorld = buffer;
    lodTier = lodTierFor(scale);
  }

  void invalidate() {
    picture = null;
    _strokes = null;
    bufferedWorld = null;
    lodTier = null;
  }

  void draw(Canvas canvas, CanvasViewport vp) {
    final pic = picture;
    final buf = bufferedWorld;
    if (pic == null || buf == null) return;
    canvas.save();
    canvas.transform(vp.matrix.storage);
    canvas.translate(buf.left, buf.top);
    canvas.drawPicture(pic);
    canvas.restore();
  }
}

// ══════════════════════════════════════════════════════════════════
// HandwritingCanvas
// ══════════════════════════════════════════════════════════════════
class HandwritingCanvas extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final ScrollController? horizontalScrollController;
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;
  final bool suppressTouchScroll;

  /// When true, pan/zoom use [canvasViewportProvider] and strokes are stored
  /// in world coordinates. Finite sheet mode keeps scroll controllers.
  final bool infiniteMode;

  const HandwritingCanvas({
    super.key,
    this.scrollController,
    this.horizontalScrollController,
    required this.zoomLevel,
    required this.onZoomChanged,
    this.suppressTouchScroll = false,
    this.infiniteMode = false,
  });

  @override
  ConsumerState<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends ConsumerState<HandwritingCanvas>
    with TickerProviderStateMixin {
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
  final _infiniteHlCache = _InfinitePictureCache();
  final _infiniteInkCache = _InfinitePictureCache();

  // Cached bounds per stroke id for fast eraser / cluster hit-tests.
  final _boundsCache = <String, Rect>{};

  // Eraser gesture session — one undo checkpoint per drag.
  bool _eraseGestureActive = false;
  bool _eraseUndoPushed = false;
  Offset? _lastErasePos;
  /// Live brush preview under the pointer (eraser tool).
  final _eraserPreview = EraserPreviewState();
  Timer? _eraserHoverHideTimer;

  // Touch tracking for palm-rejection scroll/zoom
  final _touchPointers = <int, Offset>{};
  final _touchVelocity = <int, VelocityTracker>{};
  late final PanFling _panFling;
  bool _touchPinched = false;
  double? _pinchInitialDistance;
  double? _pinchInitialZoom;
  /// Canvas-local point under the pinch midpoint when the gesture began.
  Offset? _pinchContentFocal;
  bool _pinchScrollScheduled = false;
  double? _pendingHScroll;
  double? _pendingVScroll;

  // Multi-finger tap → undo / redo
  static const double _multiTapSlop = 24.0;
  final _multiTapDownPos = <int, Offset>{};
  int _multiTapPeakCount = 0;
  bool _multiTapInvalid = false;

  // S Pen / stylus side-button → temporary eraser
  bool _sPenEraserActive = false;
  CanvasTool? _toolBeforeSPenEraser;

  // Hold-and-pause shape snap
  // Stylus devices keep emitting tiny move events while "held still";
  // movement below this screen-space threshold does not reset the pause
  // timer (so snap can fire). Drawing samples are still recorded.
  static const _shapeSnapPauseSlop = 6.0;
  final _pauseTimers = <int, Timer>{};
  final _pauseAnchorLocal = <int, Offset>{};
  final _liveSnap = <int, ({ShapeType type, List<double> vertices})>{};

  final _uuid = const Uuid();
  final _shapeRecognizer = SmartShapeRecognizer();

  List<Stroke>? _lastStrokesRef;
  double? _lastStreamline;
  Map<PenStyle, double>? _lastSensitivity;

  void _tick() => _repaintTick.value++;

  @override
  void initState() {
    super.initState();
    _panFling = PanFling(vsync: this, onPanDelta: _applyTouchPanDelta);
  }

  // ── Input handlers ─────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent e) {
    _updateSPenEraserFromEvent(e);
    _panFling.stop();

    final isPenMode = ref.read(isPenModeActiveProvider);
    final stylusOnly = ref.read(stylusOnlyModeProvider);
    final multiTapEnabled = _multiFingerTapEnabled;

    if (e.kind == PointerDeviceKind.touch) {
      if (multiTapEnabled) {
        _multiTapDownPos[e.pointer] = e.position;
        _multiTapPeakCount = max(_multiTapPeakCount, _multiTapDownPos.length);
        if (_multiTapDownPos.length >= 2) {
          _abortActiveTouchStrokes();
          // Track fingers for a possible pinch, but do not start zoom until
          // movement exceeds the tap slop (avoids tap→zoom flicker).
          for (final entry in _multiTapDownPos.entries) {
            _touchPointers.putIfAbsent(entry.key, () => entry.value);
          }
          return;
        }
      }

      if (!isPenMode || stylusOnly) {
        if (_touchPointers.isEmpty) _touchPinched = false;
        _touchPointers[e.pointer] = e.position;
        _touchVelocity[e.pointer] = VelocityTracker.withKind(e.kind)
          ..addPosition(e.timeStamp, e.position);
        // Defer pinch while a multi-finger tap may still resolve.
        if (!multiTapEnabled || _multiTapDownPos.length < 2) {
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
    }

    if (!isPenMode) return;

    if (stylusOnly &&
        e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    final tool = ref.read(activeCanvasToolProvider);
    if (tool == CanvasTool.lasso ||
        tool == CanvasTool.smelt ||
        tool == CanvasTool.text) {
      return;
    }
    if (tool == CanvasTool.eraser) {
      _beginEraseGesture();
      _setEraserPreview(e.localPosition);
      _eraseAlong(e.localPosition);
      return;
    }

    final settings = ref.read(penSettingsProvider);
    final color = ref.read(canvasColorProvider);
    final mod = ref.read(strokeWidthModifierProvider);

    final isHL = tool == CanvasTool.highlighter;
    double bWidth = 1.5 * mod;
    if (tool == CanvasTool.brush) bWidth = 3.0 * mod;
    if (isHL) bWidth = 22.0 * mod;
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

    final inkFamily = switch (tool) {
      CanvasTool.brush => InkFamily.brush,
      CanvasTool.highlighter => InkFamily.highlighter,
      _ => InkFamily.pen,
    };
    final effectiveColor = (tool == CanvasTool.pen ||
            tool == CanvasTool.brush ||
            tool == CanvasTool.highlighter)
        ? settings.effectiveColor(color, inkFamily)
        : color;

    _activeIsHighlighter[e.pointer] = isHL;
    _activePenStyle[e.pointer] = style;
    _activeColor[e.pointer] = effectiveColor;
    _activeWidth[e.pointer] = bWidth;
    _activeStrokes[e.pointer] = [_makePoint(e)];
    _pauseAnchorLocal[e.pointer] = e.localPosition;
    _liveSnap.remove(e.pointer);
    _armPauseTimer(e.pointer);
    _tick();
  }

  void _onPointerMove(PointerMoveEvent e) {
    _updateSPenEraserFromEvent(e);

    if (e.kind == PointerDeviceKind.touch) {
      final down = _multiTapDownPos[e.pointer];
      if (down != null &&
          !_multiTapInvalid &&
          (e.position - down).distance > _multiTapSlop) {
        _multiTapInvalid = true;
        _beginPinchFromTouchesIfReady();
      }
    }

    if (e.kind == PointerDeviceKind.touch &&
        _touchPointers.containsKey(e.pointer)) {
      _touchVelocity[e.pointer]?.addPosition(e.timeStamp, e.position);
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

    // Eraser: only while a down-gesture is active — never start erase from hover moves.
    if (tool == CanvasTool.eraser) {
      if (!_eraseGestureActive) return;
      _setEraserPreview(e.localPosition);
      _eraseAlong(e.localPosition);
      return;
    }

    final points = _activeStrokes[e.pointer];
    if (points == null) return;

    if (tool == CanvasTool.lasso || tool == CanvasTool.smelt) return;

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

    final pt = _makePoint(e);
    final scale = widget.infiniteMode
        ? ref.read(canvasViewportProvider).scale
        : 1.0;
    // Always keep drawing samples. The 6px pause slop is only for hold-to-snap
    // — using it to replace the last point made slow curves look like the
    // line tool (a rubber-band from the last vertex to the pen).
    appendInterpolated(points, [pt], maxGap: strokeMaxGap(scale));

    final beautify = ref.read(penSettingsProvider).beautify;
    if (beautify) {
      final anchor = _pauseAnchorLocal[e.pointer];
      if (anchor == null ||
          (e.localPosition - anchor).distance >= _shapeSnapPauseSlop) {
        _pauseAnchorLocal[e.pointer] = e.localPosition;
        _liveSnap.remove(e.pointer);
        _armPauseTimer(e.pointer);
      }
    }

    _tick();
  }

  void _onPointerUp(PointerUpEvent e) {
    _updateSPenEraserFromEvent(e);

    final wasMultiTapFinger = _multiTapDownPos.remove(e.pointer) != null;
    if (wasMultiTapFinger && _multiTapDownPos.isEmpty) {
      _finishMultiFingerTap();
    }

    if (_touchPointers.remove(e.pointer) != null) {
      final tracker = _touchVelocity.remove(e.pointer);
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
        _pinchContentFocal = null;
      }
      _maybeFlingTouchPan(tracker);
      return;
    }

    // Multi-tap may have aborted the stroke already; still clean up if present.
    if (wasMultiTapFinger && !_activeStrokes.containsKey(e.pointer)) {
      return;
    }

    _endEraseGesture();
    _cancelPauseTimer(e.pointer);
    _pauseAnchorLocal.remove(e.pointer);
    final points = _activeStrokes.remove(e.pointer);
    final isHL = _activeIsHighlighter.remove(e.pointer) ?? false;
    final style = _activePenStyle.remove(e.pointer) ?? PenStyle.pen;
    final color = _activeColor.remove(e.pointer) ?? ScrapTheme.primaryText;
    final bWidth = _activeWidth.remove(e.pointer) ?? 1.5;
    final snap = _liveSnap.remove(e.pointer);

    _eraserHoverHideTimer?.cancel();
    _eraserHoverHideTimer = null;
    _setEraserPreview(null);

    if (points == null || points.isEmpty) {
      _tick();
      return;
    }

    final tool = ref.read(activeCanvasToolProvider);
    final settings = ref.read(penSettingsProvider);

    if (tool == CanvasTool.lasso || tool == CanvasTool.smelt) {
      _tick();
      return;
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
      _infiniteHlCache.invalidate();
    } else {
      _inkCache.invalidate();
      _infiniteInkCache.invalidate();
    }
    ref.read(strokesProvider.notifier).addStroke(stroke);
    if (widget.infiniteMode) {
      ref.read(canvasViewportProvider.notifier).onStrokeCommitted(stroke);
    }
    _tick();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    final isStylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (isStylus && _sPenEraserActive) {
      _exitSPenEraser();
    } else {
      _updateSPenEraserFromEvent(e);
    }

    _multiTapDownPos.remove(e.pointer);
    if (_multiTapDownPos.isEmpty) {
      _multiTapPeakCount = 0;
      _multiTapInvalid = false;
    }

    if (_touchPointers.remove(e.pointer) != null) {
      _touchVelocity.remove(e.pointer);
      if (_touchPointers.length < 2) {
        _pinchInitialDistance = null;
        _pinchInitialZoom = null;
        _pinchContentFocal = null;
      }
    }
    _endEraseGesture();
    _cancelPauseTimer(e.pointer);
    _pauseAnchorLocal.remove(e.pointer);
    _activeStrokes.remove(e.pointer);
    _activeIsHighlighter.remove(e.pointer);
    _activePenStyle.remove(e.pointer);
    _activeColor.remove(e.pointer);
    _activeWidth.remove(e.pointer);
    _liveSnap.remove(e.pointer);
    _setEraserPreview(null);
    _tick();
  }

  bool get _multiFingerTapEnabled =>
      ref.read(twoFingerTapUndoEnabledProvider) ||
      ref.read(threeFingerTapRedoEnabledProvider);

  void _abortActiveTouchStrokes() {
    var changed = false;
    for (final pointer in _multiTapDownPos.keys.toList()) {
      if (_activeStrokes.remove(pointer) != null) changed = true;
      _activeIsHighlighter.remove(pointer);
      _activePenStyle.remove(pointer);
      _activeColor.remove(pointer);
      _activeWidth.remove(pointer);
      _liveSnap.remove(pointer);
      _pauseAnchorLocal.remove(pointer);
      _cancelPauseTimer(pointer);
    }
    if (changed) _tick();
  }

  void _finishMultiFingerTap() {
    final peak = _multiTapPeakCount;
    final invalid = _multiTapInvalid;
    _multiTapPeakCount = 0;
    _multiTapInvalid = false;
    if (invalid) return;

    if (peak == 2 && ref.read(twoFingerTapUndoEnabledProvider)) {
      undoCanvas(ref);
    } else if (peak == 3 && ref.read(threeFingerTapRedoEnabledProvider)) {
      redoCanvas(ref);
    }
  }

  bool _isStylusButtonHeld(PointerEvent e) {
    // kSecondaryButton == kPrimaryStylusButton; kTertiaryButton covers
    // secondary stylus buttons on some pens.
    return (e.buttons & kSecondaryButton) != 0 ||
        (e.buttons & kTertiaryButton) != 0;
  }

  void _updateSPenEraserFromEvent(PointerEvent e) {
    final isStylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (!isStylus) return;

    final enabled = ref.read(sPenButtonEraserEnabledProvider);
    final held = enabled && _isStylusButtonHeld(e);

    if (held && !_sPenEraserActive) {
      _enterSPenEraser(
        contactLocalPos: e.down ? e.localPosition : null,
      );
    } else if (!held && _sPenEraserActive) {
      _exitSPenEraser();
    }
  }

  void _enterSPenEraser({Offset? contactLocalPos}) {
    final current = ref.read(activeCanvasToolProvider);
    if (current != CanvasTool.eraser) {
      _toolBeforeSPenEraser = current;
      // Drop any in-progress ink stroke before switching tools.
      if (_activeStrokes.isNotEmpty) {
        for (final pointer in _activeStrokes.keys.toList()) {
          _cancelPauseTimer(pointer);
        }
        _activeStrokes.clear();
        _activeIsHighlighter.clear();
        _activePenStyle.clear();
        _activeColor.clear();
        _activeWidth.clear();
        _liveSnap.clear();
        _pauseAnchorLocal.clear();
        _tick();
      }
      ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.eraser;
      ref.read(isPenModeActiveProvider.notifier).state = true;
    } else {
      _toolBeforeSPenEraser = null;
    }
    _sPenEraserActive = true;

    // Tip already down with button held — start erasing on this contact.
    if (contactLocalPos != null && !_eraseGestureActive) {
      _beginEraseGesture();
      _setEraserPreview(contactLocalPos);
      _eraseAlong(contactLocalPos);
    }
  }

  void _exitSPenEraser() {
    if (!_sPenEraserActive) return;
    _sPenEraserActive = false;
    final prev = _toolBeforeSPenEraser;
    _toolBeforeSPenEraser = null;
    _endEraseGesture();
    _setEraserPreview(null);
    if (prev != null &&
        ref.read(activeCanvasToolProvider) == CanvasTool.eraser) {
      ref.read(activeCanvasToolProvider.notifier).state = prev;
    }
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

  /// Convert pointer-local (screen / sheet) coords to stroke world coords.
  Offset _toWorld(Offset local) {
    if (!widget.infiniteMode) return local;
    return ref.read(canvasViewportProvider).toWorld(local);
  }

  RenderBox? _scrollViewportBox() {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return null;
    return sc.position.context.storageContext.findRenderObject() as RenderBox?;
  }

  /// Canvas-local / world point currently under the pinch midpoint.
  Offset? _canvasPointUnderPinch(List<Offset> globalPositions) {
    if (widget.infiniteMode) {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      final mid = Offset(
        (globalPositions[0].dx + globalPositions[1].dx) / 2,
        (globalPositions[0].dy + globalPositions[1].dy) / 2,
      );
      final local = box.globalToLocal(mid);
      return ref.read(canvasViewportProvider).toWorld(local);
    }

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
    final h = widget.horizontalScrollController?.hasClients == true
        ? widget.horizontalScrollController!.offset
        : 0.0;
    final v = widget.scrollController?.offset ?? 0.0;
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
      if (vScroll != null && vScroll.hasClients) {
        vScroll.jumpTo(
          targetV.clamp(0.0, vScroll.position.maxScrollExtent),
        );
      }
      final hScroll = widget.horizontalScrollController;
      if (hScroll != null && hScroll.hasClients) {
        hScroll.jumpTo(
          targetH.clamp(0.0, hScroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _handleTouchMove(PointerMoveEvent e) {
    final previous = _touchPointers[e.pointer];
    _touchPointers[e.pointer] = e.position;

    // Pending multi-finger tap: ignore jitter so zoom/pan doesn't flicker.
    if (_multiTapDownPos.length >= 2 && !_multiTapInvalid) {
      return;
    }

    if (_touchPointers.length == 2 &&
        _pinchInitialDistance != null &&
        _pinchInitialZoom != null &&
        _pinchContentFocal != null) {
      _touchPinched = true;
      final positions = _touchPointers.values.toList();
      final currentDistance = (positions[0] - positions[1]).distance;
      if (currentDistance <= 5.0) return;

      if (widget.infiniteMode) {
        final newZoom =
            (_pinchInitialZoom! * (currentDistance / _pinchInitialDistance!))
                .clamp(
              CanvasViewport.minScaleInfinite,
              CanvasViewport.maxScaleInfinite,
            );
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          ref.read(canvasViewportProvider.notifier).setViewport(
                CanvasViewport(
                  pan: ref.read(canvasViewportProvider).pan,
                  scale: newZoom,
                ),
              );
          widget.onZoomChanged(newZoom);
          return;
        }
        final mid = Offset(
          (positions[0].dx + positions[1].dx) / 2,
          (positions[0].dy + positions[1].dy) / 2,
        );
        final focalScreen = box.globalToLocal(mid);
        final worldFocal = _pinchContentFocal!;
        final newPan = Offset(
          worldFocal.dx - focalScreen.dx / newZoom,
          worldFocal.dy - focalScreen.dy / newZoom,
        );
        ref.read(canvasViewportProvider.notifier).setViewport(
              CanvasViewport(pan: newPan, scale: newZoom),
            );
        widget.onZoomChanged(newZoom);
        return;
      }

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
    } else if (previous != null && !widget.suppressTouchScroll) {
      if (!ref.read(isPenModeActiveProvider)) return;
      _applyTouchPanDelta(e.position - previous);
    }
  }

  void _applyTouchPanDelta(Offset delta) {
    if (widget.suppressTouchScroll) return;
    if (widget.infiniteMode) {
      ref.read(canvasViewportProvider.notifier).panByScreenDelta(delta);
      return;
    }
    final vScroll = widget.scrollController;
    if (vScroll == null || !vScroll.hasClients) return;
    vScroll.jumpTo(
      (vScroll.offset - delta.dy)
          .clamp(0.0, vScroll.position.maxScrollExtent),
    );
    final hScroll = widget.horizontalScrollController;
    if (hScroll != null && hScroll.hasClients) {
      hScroll.jumpTo(
        (hScroll.offset - delta.dx)
            .clamp(0.0, hScroll.position.maxScrollExtent),
      );
    }
  }

  void _maybeFlingTouchPan(VelocityTracker? tracker) {
    if (!mounted) return;
    if (_touchPointers.isNotEmpty || _touchPinched) return;
    if (widget.suppressTouchScroll) return;
    if (!ref.read(isPenModeActiveProvider)) return;
    final velocity = tracker?.getVelocity() ?? Velocity.zero;
    _panFling.start(velocity.pixelsPerSecond);
  }

  /// Start pinch using the current finger span so zoom doesn't jump when a
  /// multi-finger gesture graduates from tap → pinch.
  void _beginPinchFromTouchesIfReady() {
    if (_pinchInitialDistance != null) return;
    if (_touchPointers.length != 2) return;
    final positions = _touchPointers.values.toList();
    final distance = (positions[0] - positions[1]).distance;
    if (distance <= 5.0) return;
    _pinchInitialDistance = distance;
    _pinchInitialZoom = widget.zoomLevel;
    _pinchContentFocal = _canvasPointUnderPinch(positions);
  }

  void _beginEraseGesture() {
    _eraserHoverHideTimer?.cancel();
    _eraserHoverHideTimer = null;
    _eraseGestureActive = true;
    _eraseUndoPushed = false;
    _lastErasePos = null;
  }

  void _endEraseGesture() {
    _eraseGestureActive = false;
    _eraseUndoPushed = false;
    _lastErasePos = null;
  }

  void _setEraserPreview(Offset? pos) {
    _eraserPreview.pos = pos;
  }

  /// Stylus proximity preview — auto-hides if hover events stop (pen left range).
  void _setEraserHoverPreview(Offset pos) {
    if (_eraseGestureActive) return; // contact erase owns the ring
    _eraserHoverHideTimer?.cancel();
    _setEraserPreview(pos);
    _eraserHoverHideTimer = Timer(const Duration(milliseconds: 80), () {
      if (!_eraseGestureActive) _setEraserPreview(null);
    });
  }

  /// Eraser radius from the toolbar thickness dots (same control as pen width).
  /// In infinite mode this is a world-space radius so on-screen size stays stable.
  double _eraserRadius() {
    final screenR = eraserScreenRadius(ref.read(strokeWidthModifierProvider));
    if (widget.infiniteMode) {
      final scale = ref.read(canvasViewportProvider).scale;
      return screenR / max(scale, 0.01);
    }
    return screenR;
  }

  /// Sample along the drag path so fast strokes don't skip ink.
  void _eraseAlong(Offset localPos) {
    final pos = _toWorld(localPos);
    final radius = _eraserRadius();
    for (final sample in sampleErasePath(_lastErasePos, pos, radius)) {
      _eraseAt(sample, radius);
    }
    _lastErasePos = pos;
  }

  void _eraseAt(Offset pos, double radius) {
    final mode = ref.read(penSettingsProvider).eraser;
    if (mode == EraserMode.area) {
      _eraseAreaAt(pos, radius);
    } else {
      _eraseStrokesAt(pos, radius);
    }
  }

  void _eraseStrokesAt(Offset pos, double radius) {
    final strokes = ref.read(strokesProvider);
    final toHide = <String>[];
    final pad = radius + 4;
    for (final s in strokes) {
      if (s.isHidden) continue;
      final bounds = _boundsCache.putIfAbsent(
        s.id,
        () => InkRenderer.boundsOf(s.points, pad: pad),
      );
      if (!bounds.inflate(pad).contains(pos)) continue;
      if (_strokeNearPoint(s, pos, radius: radius)) toHide.add(s.id);
    }
    if (toHide.isEmpty) return;

    _hlCache.invalidate();
    _inkCache.invalidate();
    _infiniteHlCache.invalidate();
    _infiniteInkCache.invalidate();
    for (final id in toHide) {
      _boundsCache.remove(id);
    }
    final pushUndo = !_eraseUndoPushed;
    ref
        .read(strokesProvider.notifier)
        .hideStrokes(toHide, pushUndo: pushUndo);
    _eraseUndoPushed = true;
    if (widget.infiniteMode) {
      ref.read(canvasViewportProvider.notifier).onStrokesChanged();
    }
  }

  void _eraseAreaAt(Offset pos, double radius) {
    final strokes = ref.read(strokesProvider);
    final updates = <Stroke>[];
    final additions = <Stroke>[];
    final deleteIds = <String>[];
    final hideIds = <String>[];
    final pad = radius + 4;

    for (final s in strokes) {
      if (s.isHidden || s.points.isEmpty) continue;
      final bounds = _boundsCache.putIfAbsent(
        s.id,
        () => InkRenderer.boundsOf(s.points, pad: pad),
      );
      if (!bounds.inflate(pad).contains(pos)) continue;

      // Geometric shapes: remove the whole stroke when the brush hits.
      if (s.shapeType != ShapeType.none) {
        if (_strokeNearPoint(s, pos, radius: radius)) hideIds.add(s.id);
        continue;
      }

      final keptRuns = carveStrokePoints(s.points, pos, radius);
      if (keptRuns.length == 1 && keptRuns.first.length == s.points.length) {
        continue;
      }
      if (keptRuns.isEmpty) {
        deleteIds.add(s.id);
        continue;
      }

      // First surviving run keeps the original id; extras become new strokes.
      updates.add(
        s.copyWith(
          points: keptRuns.first,
          isStraightLine: false,
          shapeType: ShapeType.none,
          shapeVertices: const [],
        ),
      );
      for (var i = 1; i < keptRuns.length; i++) {
        additions.add(s.withPoints(_uuid.v4(), keptRuns[i]));
      }
    }

    if (updates.isEmpty &&
        additions.isEmpty &&
        deleteIds.isEmpty &&
        hideIds.isEmpty) {
      return;
    }

    _hlCache.invalidate();
    _inkCache.invalidate();
    _infiniteHlCache.invalidate();
    _infiniteInkCache.invalidate();
    for (final id in [
      ...deleteIds,
      ...hideIds,
      ...updates.map((u) => u.id),
    ]) {
      _boundsCache.remove(id);
    }
    for (final s in [...updates, ...additions]) {
      _boundsCache[s.id] =
          InkRenderer.boundsOf(s.points, pad: s.baseWidth);
    }

    final pushUndo = !_eraseUndoPushed;
    ref.read(strokesProvider.notifier).applyEraserMutation(
          hideIds: hideIds,
          deleteIds: deleteIds,
          updates: updates,
          additions: additions,
          pushUndo: pushUndo,
        );
    _eraseUndoPushed = true;
    if (widget.infiniteMode) {
      ref.read(canvasViewportProvider.notifier).onStrokesChanged();
    }
  }

  bool _strokeNearPoint(Stroke s, Offset pos, {double radius = 20}) {
    if (pointsNearPoint(s.points, pos, radius: radius)) return true;
    // Shape strokes may have sparse/empty freehand points — use vertices.
    if (s.shapeType != ShapeType.none && s.shapeVertices.length >= 2) {
      final r2 = radius * radius;
      final verts = s.shapeVertices;
      for (var i = 0; i + 1 < verts.length; i += 2) {
        final a = Offset(verts[i], verts[i + 1]);
        if ((a - pos).distanceSquared <= r2) return true;
        if (i + 3 < verts.length) {
          final b = Offset(verts[i + 2], verts[i + 3]);
          if (distToSegmentSq(pos, a, b) <= r2) return true;
        }
      }
    }
    return false;
  }

  StrokePoint _makePoint(PointerEvent e) {
    final world = _toWorld(e.localPosition);
    return StrokePoint(
      x: world.dx,
      y: world.dy,
      pressure: e.pressure > 0 ? e.pressure : 1.0,
      timestamp: e.timeStamp.inMicroseconds,
    );
  }

  @override
  void dispose() {
    _eraserHoverHideTimer?.cancel();
    for (final t in _pauseTimers.values) {
      t.cancel();
    }
    // Don't mutate providers during dispose — just clear local temp-eraser state.
    _sPenEraserActive = false;
    _toolBeforeSPenEraser = null;
    _repaintTick.dispose();
    _panFling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strokes = ref.watch(strokesProvider);
    final pageConfig = ref.watch(pageLayoutProvider);
    final pageStyle = pageConfig.style;
    final penSettings = ref.watch(penSettingsProvider);
    final activeTool = ref.watch(activeCanvasToolProvider);
    final widthMod = ref.watch(strokeWidthModifierProvider);
    final eraserRadius = eraserScreenRadius(widthMod);
    final showEraserPreview = activeTool == CanvasTool.eraser;
    _eraserPreview.radius = eraserRadius;
    _eraserPreview.mode = penSettings.eraser;
    if (!showEraserPreview) {
      _eraserHoverHideTimer?.cancel();
      _eraserHoverHideTimer = null;
      _eraserPreview.pos = null;
    } else if (!_eraseGestureActive &&
        _eraserHoverHideTimer == null &&
        _eraserPreview.pos != null) {
      // Drop a stuck ring (e.g. hover ended without a clear event).
      _eraserPreview.pos = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tick();
      });
    }

    // Invalidate caches only when the stroke list identity changes.
    if (!identical(_lastStrokesRef, strokes)) {
      _lastStrokesRef = strokes;
      _hlCache.invalidate();
      _inkCache.invalidate();
      _infiniteHlCache.invalidate();
      _infiniteInkCache.invalidate();
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
      _infiniteInkCache.invalidate();
    }

    final hlStrokes =
        strokes.where((s) => !s.isHidden && s.isHighlighter).toList();
    final inkStrokes =
        strokes.where((s) => !s.isHidden && !s.isHighlighter).toList();

    final CanvasViewport? viewport =
        widget.infiniteMode ? ref.watch(canvasViewportProvider) : null;
    final StrokeSpatialIndex? spatialIndex =
        widget.infiniteMode ? ref.watch(strokeSpatialIndexProvider) : null;

    return RepaintBoundary(
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerHover: (e) {
          _updateSPenEraserFromEvent(e);
          // Stylus proximity only; ring auto-clears when hover events stop.
          if (ref.read(activeCanvasToolProvider) != CanvasTool.eraser) return;
          if (e.kind != PointerDeviceKind.stylus &&
              e.kind != PointerDeviceKind.invertedStylus) {
            return;
          }
          _setEraserHoverPreview(e.localPosition);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: background + committed highlighters
            CustomPaint(
              painter: _HighlightLayerPainter(
                strokes: hlStrokes,
                pageLayout: pageStyle,
                cache: _hlCache,
                infiniteCache: _infiniteHlCache,
                allStrokes: strokes,
                viewport: viewport,
                spatialIndex: spatialIndex,
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
                  viewport: viewport,
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
                infiniteCache: _infiniteInkCache,
                allStrokes: strokes,
                streamline: penSettings.streamline,
                sensitivityMap: penSettings.sensitivity,
                viewport: viewport,
                spatialIndex: spatialIndex,
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
                  viewport: viewport,
                  repaint: _repaintTick,
                ),
                size: Size.infinite,
              ),
            ),
            // Layer 5: eraser brush size — only while erasing / stylus hover
            if (showEraserPreview)
              CustomPaint(
                painter: EraserPreviewPainter(
                  preview: _eraserPreview,
                  radius: eraserRadius,
                  mode: penSettings.eraser,
                ),
                size: Size.infinite,
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
  final _InfinitePictureCache infiniteCache;
  final CanvasViewport? viewport;
  final StrokeSpatialIndex? spatialIndex;

  _HighlightLayerPainter({
    required this.strokes,
    required this.allStrokes,
    required this.pageLayout,
    required this.cache,
    required this.infiniteCache,
    this.viewport,
    this.spatialIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vp = viewport;
    if (vp != null) {
      _paintInfinite(canvas, size, vp);
      return;
    }

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

  void _paintInfinite(Canvas canvas, Size size, CanvasViewport vp) {
    canvas.drawColor(ScrapTheme.background, BlendMode.srcOver);
    final visible = vp.visibleWorld(size);
    _drawInfinitePageLines(canvas, size, vp, visible, pageLayout);

    // Drop highlighter layer at very low zoom.
    if (vp.scale < 0.15) return;

    final query = visible.inflate(
      max(visible.width, visible.height),
    );
    final visibleStrokes = spatialIndex != null
        ? spatialIndex!.queryStrokes(strokes, query)
        : strokes;

    if (!infiniteCache.isValid(allStrokes, visible, vp.scale)) {
      final buffer = visible.inflate(
        max(visible.width, visible.height),
      );
      infiniteCache.build(allStrokes, buffer, vp.scale, (c, buf) {
        final lod = _InfinitePictureCache.lodTierFor(vp.scale);
        for (final stroke in visibleStrokes) {
          if (!buf.overlaps(
              InkRenderer.boundsOf(stroke.points, pad: stroke.baseWidth))) {
            continue;
          }
          if (lod <= 1) {
            _paintStrokeLod(c, stroke, lod);
          } else {
            InkRenderer.paintStroke(c, stroke);
          }
        }
      });
    }
    infiniteCache.draw(canvas, vp);
  }

  @override
  bool shouldRepaint(covariant _HighlightLayerPainter old) =>
      old.pageLayout != pageLayout ||
      !identical(old.allStrokes, allStrokes) ||
      old.viewport != viewport;
}

// ══════════════════════════════════════════════════════════════════
// Layer 3 — committed ink (non-highlighter)
// ══════════════════════════════════════════════════════════════════
class _InkLayerPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Stroke> allStrokes;
  final _StrokeCache cache;
  final _InfinitePictureCache infiniteCache;
  final double streamline;
  final Map<PenStyle, double> sensitivityMap;
  final CanvasViewport? viewport;
  final StrokeSpatialIndex? spatialIndex;

  _InkLayerPainter({
    required this.strokes,
    required this.allStrokes,
    required this.cache,
    required this.infiniteCache,
    required this.streamline,
    required this.sensitivityMap,
    this.viewport,
    this.spatialIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final vp = viewport;
    if (vp != null) {
      _paintInfinite(canvas, size, vp);
      return;
    }

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
              sensitivity: sensitivityMap[stroke.penStyle] ?? 0.5,
            );
          }
        }
      });
    }
    canvas.drawPicture(cache.picture!);
  }

  void _paintInfinite(Canvas canvas, Size size, CanvasViewport vp) {
    final visible = vp.visibleWorld(size);
    final query = visible.inflate(
      max(visible.width, visible.height),
    );
    final visibleStrokes = spatialIndex != null
        ? spatialIndex!.queryStrokes(strokes, query)
        : strokes;

    if (!infiniteCache.isValid(allStrokes, visible, vp.scale)) {
      final buffer = visible.inflate(
        max(visible.width, visible.height),
      );
      infiniteCache.build(allStrokes, buffer, vp.scale, (c, buf) {
        final lod = _InfinitePictureCache.lodTierFor(vp.scale);
        for (final stroke in visibleStrokes) {
          final bounds = stroke.shapeType != ShapeType.none &&
                  stroke.shapeVertices.isNotEmpty
              ? _shapeBounds(stroke)
              : InkRenderer.boundsOf(stroke.points, pad: stroke.baseWidth);
          if (bounds == null || !buf.overlaps(bounds)) continue;

          if (stroke.shapeType != ShapeType.none &&
              stroke.shapeVertices.isNotEmpty) {
            _paintShape(c, stroke);
          } else if (lod <= 1) {
            _paintStrokeLod(c, stroke, lod);
          } else {
            InkRenderer.paint(
              canvas: c,
              pts: stroke.points,
              color: stroke.color,
              baseWidth: stroke.baseWidth,
              style: stroke.penStyle,
              isHighlighter: false,
              streamline: streamline,
              sensitivity: sensitivityMap[stroke.penStyle] ?? 0.5,
            );
          }
        }
      });
    }
    infiniteCache.draw(canvas, vp);
  }

  @override
  bool shouldRepaint(covariant _InkLayerPainter old) =>
      !identical(old.allStrokes, allStrokes) ||
      old.streamline != streamline ||
      old.viewport != viewport;
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
  final CanvasViewport? viewport;

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
    this.viewport,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = viewport;
    if (vp != null) {
      canvas.save();
      canvas.transform(vp.matrix.storage);
    }

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

    if (vp != null) canvas.restore();
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

/// Procedural infinite-canvas background drawn in screen space from visible
/// world bounds. Cost is O(visible cells), never walks from world origin.
void _drawInfinitePageLines(
  Canvas canvas,
  Size screenSize,
  CanvasViewport vp,
  Rect visible,
  PageLayout pageLayout,
) {
  if (pageLayout == PageLayout.plain) return;

  const spacing = 36.0;
  // Skip subdivisions when cells would be tiny on screen.
  if (spacing * vp.scale < 6) return;

  final p = Paint()
    ..color = ScrapTheme.notebookLines.withValues(alpha: 0.55)
    ..strokeWidth = 0.7;

  final left = (visible.left / spacing).floor() * spacing;
  final top = (visible.top / spacing).floor() * spacing;
  final right = visible.right;
  final bottom = visible.bottom;

  if (pageLayout == PageLayout.dotted) {
    final dp = Paint()
      ..color = ScrapTheme.notebookLines.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final r = max(1.0, 1.5 * vp.scale);
    for (double y = top; y <= bottom; y += spacing) {
      for (double x = left; x <= right; x += spacing) {
        canvas.drawCircle(vp.toScreen(Offset(x, y)), r, dp);
      }
    }
    return;
  }

  if (pageLayout == PageLayout.ruled) {
    for (double y = top; y <= bottom; y += spacing) {
      final a = vp.toScreen(Offset(visible.left, y));
      final b = vp.toScreen(Offset(visible.right, y));
      canvas.drawLine(a, b, p);
    }
    return;
  }

  // Grid
  for (double y = top; y <= bottom; y += spacing) {
    final a = vp.toScreen(Offset(visible.left, y));
    final b = vp.toScreen(Offset(visible.right, y));
    canvas.drawLine(a, b, p);
  }
  for (double x = left; x <= right; x += spacing) {
    final a = vp.toScreen(Offset(x, visible.top));
    final b = vp.toScreen(Offset(x, visible.bottom));
    canvas.drawLine(a, b, p);
  }
}

void _paintStrokeLod(Canvas canvas, Stroke stroke, int lod) {
  if (stroke.points.isEmpty) return;
  final paint = Paint()
    ..color = stroke.color
    ..style = PaintingStyle.stroke
    ..strokeWidth = max(0.5, stroke.baseWidth * (lod == 0 ? 0.6 : 0.85))
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final path = Path()
    ..moveTo(stroke.points.first.x, stroke.points.first.y);
  // Low LOD: stride through points for cheaper polylines.
  final step = lod == 0 ? 4 : 2;
  for (var i = step; i < stroke.points.length; i += step) {
    path.lineTo(stroke.points[i].x, stroke.points[i].y);
  }
  final last = stroke.points.last;
  path.lineTo(last.x, last.y);
  canvas.drawPath(path, paint);
}

Rect? _shapeBounds(Stroke stroke) {
  final v = stroke.shapeVertices;
  if (v.length < 2) return null;
  double? minX, minY, maxX, maxY;
  for (var i = 0; i + 1 < v.length; i += 2) {
    final x = v[i];
    final y = v[i + 1];
    minX = minX == null ? x : min(minX, x);
    minY = minY == null ? y : min(minY, y);
    maxX = maxX == null ? x : max(maxX, x);
    maxY = maxY == null ? y : max(maxY, y);
  }
  if (minX == null) return null;
  return Rect.fromLTRB(minX, minY!, maxX!, maxY!).inflate(stroke.baseWidth);
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
