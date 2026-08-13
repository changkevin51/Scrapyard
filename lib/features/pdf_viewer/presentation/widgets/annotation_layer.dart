import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/gestures/pan_fling.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../canvas/data/ink_renderer.dart';
import '../../../canvas/data/pen_engine.dart';
import '../../../canvas/data/stroke_sampler.dart';
import '../../../canvas/domain/models/stroke.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../../canvas/presentation/widgets/eraser_preview.dart';
import '../../domain/models/annotation_record.dart';
import '../providers/pdf_providers.dart';

typedef PdfSmeltSelectionHandler = void Function({
  required Rect selectionRect,
  required Future<void> Function({bool forceRefresh, bool forceCodeExecution})
      runSmelt,
  required Future<Uint8List?> Function() captureSelection,
});

class AnnotationLayer extends ConsumerStatefulWidget {
  final int pageNumber;
  final String documentId;
  final PdfPage? page;
  final PdfSmeltSelectionHandler? onSmeltSelection;

  /// pdfrx places page overlays *above* [InteractiveViewer] as siblings, so
  /// finger events never reach the viewer while a draw tool is hit-testing.
  /// We drive pan/zoom through this controller when palm rejection is on.
  final PdfViewerController? viewerController;

  /// Shared fling for finger pan; owned by the viewer so it survives page reuse.
  final PanFling? panFling;

  const AnnotationLayer({
    super.key,
    required this.pageNumber,
    required this.documentId,
    this.page,
    this.onSmeltSelection,
    this.viewerController,
    this.panFling,
  });

  @override
  ConsumerState<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends ConsumerState<AnnotationLayer> {
  final _uuid = const Uuid();
  final _eraserPreview = EraserPreviewState();
  Offset? _startPoint;
  Offset? _eraserLast;
  Rect? _smeltDraft;
  Size _layerSize = Size.zero;
  int? _activePointer;
  bool _eraseGestureActive = false;

  /// Finger/mouse pointers used for pan/pinch while a draw tool is active.
  final Map<int, Offset> _navPointers = {};
  final Map<int, VelocityTracker> _navVelocity = {};
  bool _navPinched = false;
  double? _pinchStartDistance;
  double? _pinchStartZoom;
  Offset? _pinchStartFocalDoc;

  Color _liveColor = inkBlack;
  double _liveWidth = 1.5;
  PenStyle _livePenStyle = PenStyle.pen;
  bool _liveIsHighlighter = false;

  final _livePoints = <StrokePoint>[];
  final _liveTick = ValueNotifier<int>(0);

  void _tickLiveInk() => _liveTick.value++;

  void _clearLiveInk() {
    _livePoints.clear();
    _tickLiveInk();
  }

  @override
  void dispose() {
    _liveTick.dispose();
    super.dispose();
  }

  bool _isStylus(ui.PointerDeviceKind kind) =>
      kind == ui.PointerDeviceKind.stylus ||
      kind == ui.PointerDeviceKind.invertedStylus;

  bool _shouldNavigate(ui.PointerDeviceKind kind) {
    final stylusOnly = ref.read(stylusOnlyModeProvider);
    return stylusOnly && !_isStylus(kind);
  }

  double _eraserRadius() =>
      eraserScreenRadius(ref.read(strokeWidthModifierProvider));

  double _strokeWidthFor(AnnotationTool tool, {double? mod}) {
    final double m = mod ?? ref.read(strokeWidthModifierProvider);
    if (tool == AnnotationTool.highlighter) return 22.0 * m;
    return 1.5 * m;
  }

  void _snapshotLiveStyle(AnnotationTool tool) {
    final base = ref.read(canvasColorProvider);
    final settings = ref.read(penSettingsProvider);
    final mod = ref.read(strokeWidthModifierProvider);
    _liveIsHighlighter = tool == AnnotationTool.highlighter;
    if (_liveIsHighlighter) {
      _liveColor = settings.effectiveColor(base, InkFamily.highlighter);
      _liveWidth = 22.0 * mod;
      _livePenStyle = PenStyle.pen;
    } else {
      _liveColor = settings.effectiveColor(base, InkFamily.pen);
      _liveWidth = 1.5 * mod;
      final s = settings.penStyle;
      _livePenStyle = s.family == InkFamily.pen ? s : PenStyle.pen;
    }
  }

  StrokePoint _makePoint(Offset local, PointerEvent event) {
    return StrokePoint(
      x: local.dx,
      y: local.dy,
      pressure: event.pressure > 0 ? event.pressure : 1.0,
      timestamp: event.timeStamp.inMicroseconds,
    );
  }

  void _saveCurrentStroke(Size size) {
    final inkPoints = _livePoints;
    final activeTool = ref.read(activeToolProvider);
    if (inkPoints.isEmpty) return;

    final type = switch (activeTool) {
      AnnotationTool.highlighter => AnnotationType.highlight,
      AnnotationTool.pen => AnnotationType.ink,
      AnnotationTool.shape => AnnotationType.shape,
      _ => null,
    };
    if (type == null) return;

    final convertedPoints = inkPoints
        .map((p) => {
              'x': size.width == 0 ? 0.0 : p.x / size.width,
              'y': size.height == 0 ? 0.0 : p.y / size.height,
              'pressure': p.pressure,
              'timestamp': p.timestamp,
            })
        .toList();

    final record = AnnotationRecord(
      id: _uuid.v4(),
      documentId: widget.documentId,
      pageNumber: widget.pageNumber,
      type: type,
      data: {
        'points': convertedPoints,
        'color': _liveColor.toARGB32(),
        'strokeWidth': _liveWidth,
        'normalized': true,
        'pressure': true,
        'isHighlighter': _liveIsHighlighter,
        'penStyle': _livePenStyle.name,
      },
    );

    ref.read(pdfRepositoryProvider).saveAnnotation(record).then((_) {
      ref.invalidate(pageAnnotationsProvider(widget.pageNumber));
    });

    _clearLiveInk();
    ref.read(currentInkProvider.notifier).clear();
    ref.read(currentInkPageProvider.notifier).state = null;
    _startPoint = null;
  }

  Future<void> _eraseAt(Offset localPos, Size size) async {
    final radius = _eraserRadius();
    final mode = ref.read(penSettingsProvider).eraser;
    final annotations =
        ref.read(pageAnnotationsProvider(widget.pageNumber)).value ?? [];
    if (annotations.isEmpty) return;

    if (mode == EraserMode.area) {
      await _eraseAreaAt(localPos, size, radius, annotations);
    } else {
      await _eraseStrokesAt(localPos, size, radius, annotations);
    }
  }

  Future<void> _eraseStrokesAt(
    Offset pos,
    Size size,
    double radius,
    List<AnnotationRecord> annotations,
  ) async {
    final hitIds = <String>{};
    for (final record in annotations) {
      final pts = _strokePointsOf(record, size);
      if (record.type == AnnotationType.comment) {
        if (pts.isNotEmpty &&
            (Offset(pts.first.x, pts.first.y) - pos).distance <= radius + 6) {
          hitIds.add(record.id);
        }
        continue;
      }
      if (pointsNearPoint(pts, pos, radius: radius)) {
        hitIds.add(record.id);
      }
    }
    if (hitIds.isEmpty) return;

    await ref.read(pdfRepositoryProvider).deleteAnnotations(hitIds);
    ref.invalidate(pageAnnotationsProvider(widget.pageNumber));
  }

  Future<void> _eraseAreaAt(
    Offset pos,
    Size size,
    double radius,
    List<AnnotationRecord> annotations,
  ) async {
    final repo = ref.read(pdfRepositoryProvider);
    var changed = false;

    for (final record in annotations) {
      if (record.type == AnnotationType.comment) {
        final pts = _strokePointsOf(record, size);
        if (pts.isNotEmpty &&
            (Offset(pts.first.x, pts.first.y) - pos).distance <= radius + 6) {
          await repo.deleteAnnotation(record.id);
          changed = true;
        }
        continue;
      }

      final pts = _strokePointsOf(record, size);
      if (pts.isEmpty) continue;
      if (!InkRenderer.boundsOf(pts, pad: radius + 4)
          .inflate(radius + 4)
          .contains(pos)) {
        continue;
      }

      final keptRuns = carveStrokePoints(pts, pos, radius);
      if (keptRuns.length == 1 && keptRuns.first.length == pts.length) {
        continue;
      }
      changed = true;

      if (keptRuns.isEmpty) {
        await repo.deleteAnnotation(record.id);
        continue;
      }

      // First run keeps the id; extras become new annotations.
      await repo.saveAnnotation(_recordWithPoints(record, keptRuns.first, size));
      for (var i = 1; i < keptRuns.length; i++) {
        await repo.saveAnnotation(
          _recordWithPoints(
            record,
            keptRuns[i],
            size,
            id: _uuid.v4(),
          ),
        );
      }
    }

    if (changed) {
      ref.invalidate(pageAnnotationsProvider(widget.pageNumber));
    }
  }

  AnnotationRecord _recordWithPoints(
    AnnotationRecord record,
    List<StrokePoint> pts,
    Size size, {
    String? id,
  }) {
    final normalized = size.width > 0 && size.height > 0;
    return AnnotationRecord(
      id: id ?? record.id,
      documentId: record.documentId,
      pageNumber: record.pageNumber,
      type: record.type,
      data: {
        ...record.data,
        'normalized': true,
        'points': pts
            .map((p) => {
                  'x': normalized ? p.x / size.width : p.x,
                  'y': normalized ? p.y / size.height : p.y,
                  'pressure': p.pressure,
                  'timestamp': p.timestamp,
                })
            .toList(),
      },
    );
  }

  List<StrokePoint> _strokePointsOf(AnnotationRecord record, Size size) {
    final pointsList = record.data['points'] as List<dynamic>?;
    if (pointsList == null || pointsList.isEmpty) return const [];
    final normalized = record.data['normalized'] == true;
    return pointsList.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final nx = (m['x'] as num?)?.toDouble() ?? (m['dx'] as num).toDouble();
      final ny = (m['y'] as num?)?.toDouble() ?? (m['dy'] as num).toDouble();
      return StrokePoint(
        x: normalized ? nx * size.width : nx,
        y: normalized ? ny * size.height : ny,
        pressure: (m['pressure'] as num?)?.toDouble() ?? 1.0,
        timestamp: (m['timestamp'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  void _offerSmelt(Rect localRect, Size size) {
    final page = widget.page;
    final handler = widget.onSmeltSelection;
    if (page == null || handler == null) return;
    if (localRect.width < 8 || localRect.height < 8) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final selectionRect = box.localToGlobal(localRect.topLeft) & localRect.size;

    final cacheKey =
        'pdf:${widget.documentId}:p${widget.pageNumber}:'
        '${localRect.left.toStringAsFixed(1)},'
        '${localRect.top.toStringAsFixed(1)},'
        '${localRect.width.toStringAsFixed(1)},'
        '${localRect.height.toStringAsFixed(1)}';

    Future<void> runSmelt({
      bool forceRefresh = false,
      bool forceCodeExecution = false,
    }) async {
      final notifier = ref.read(smeltProvider.notifier);
      if (!forceRefresh &&
          !forceCodeExecution &&
          notifier.hasCached(cacheKey)) {
        notifier.restoreCached(cacheKey);
        return;
      }

      notifier.startLoading(
        cacheKey: cacheKey,
        forceCodeExecution: forceCodeExecution,
      );

      Uint8List? imageBytes;
      try {
        imageBytes = await _capturePageRegion(page, localRect, size);
      } catch (_) {}

      await notifier.smelt(
        imageBytes: imageBytes,
        cacheKey: cacheKey,
        forceCodeExecution: forceCodeExecution,
      );
    }

    handler(
      selectionRect: selectionRect,
      runSmelt: runSmelt,
      captureSelection: () => _capturePageRegion(page, localRect, size),
    );
  }

  Future<Uint8List?> _capturePageRegion(
    PdfPage page,
    Rect localRect,
    Size layerSize,
  ) async {
    if (layerSize.width <= 0 || layerSize.height <= 0) return null;

    final fullWidth = layerSize.width * 2;
    final fullHeight = layerSize.height * 2;
    final fullW = fullWidth.round();
    final fullH = fullHeight.round();
    var x = (localRect.left / layerSize.width * fullWidth).round();
    var y = (localRect.top / layerSize.height * fullHeight).round();
    var w = math.max(1, (localRect.width / layerSize.width * fullWidth).round());
    var h =
        math.max(1, (localRect.height / layerSize.height * fullHeight).round());
    x = x.clamp(0, math.max(0, fullW - 1));
    y = y.clamp(0, math.max(0, fullH - 1));
    w = w.clamp(1, math.max(1, fullW - x));
    h = h.clamp(1, math.max(1, fullH - y));

    final pdfImage = await page.render(
      x: x,
      y: y,
      width: w,
      height: h,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
      backgroundColor: Colors.white,
    );
    if (pdfImage == null) return null;

    try {
      final uiImage = await pdfImage.createImage();
      try {
        final bytes =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        return bytes?.buffer.asUint8List();
      } finally {
        uiImage.dispose();
      }
    } finally {
      pdfImage.dispose();
    }
  }

  void _clearPinch() {
    _pinchStartDistance = null;
    _pinchStartZoom = null;
    _pinchStartFocalDoc = null;
  }

  void _beginPinchIfReady() {
    final controller = widget.viewerController;
    if (controller == null || !controller.isReady) return;
    if (_navPointers.length != 2) return;

    final pts = _navPointers.values.toList();
    final dist = (pts[0] - pts[1]).distance;
    if (dist < 5) return;

    final focalGlobal = Offset(
      (pts[0].dx + pts[1].dx) / 2,
      (pts[0].dy + pts[1].dy) / 2,
    );
    final focalView = controller.globalToLocal(focalGlobal);
    if (focalView == null) return;

    final m = controller.value;
    final zoom = m.zoom;
    if (zoom == 0) return;

    _pinchStartDistance = dist;
    _pinchStartZoom = zoom;
    _pinchStartFocalDoc = Offset(
      (focalView.dx - m.xZoomed) / zoom,
      (focalView.dy - m.yZoomed) / zoom,
    );
  }

  void _handleNavDown(PointerDownEvent event) {
    widget.panFling?.stop();
    if (_navPointers.isEmpty) _navPinched = false;
    _navPointers[event.pointer] = event.position;
    _navVelocity[event.pointer] = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    if (_navPointers.length >= 2) {
      _beginPinchIfReady();
    }
  }

  void _handleNavMove(PointerMoveEvent event) {
    if (!_navPointers.containsKey(event.pointer)) return;
    _navPointers[event.pointer] = event.position;
    _navVelocity[event.pointer]?.addPosition(event.timeStamp, event.position);

    final controller = widget.viewerController;
    if (controller == null || !controller.isReady) return;

    if (_navPointers.length == 1) {
      _applyPdfPanDelta(event.delta);
      return;
    }

    if (_navPointers.length >= 2 &&
        _pinchStartDistance != null &&
        _pinchStartZoom != null &&
        _pinchStartFocalDoc != null &&
        _pinchStartDistance! > 5) {
      _navPinched = true;
      final pts = _navPointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      if (dist < 5) return;

      final focalGlobal = Offset(
        (pts[0].dx + pts[1].dx) / 2,
        (pts[0].dy + pts[1].dy) / 2,
      );
      final focalView = controller.globalToLocal(focalGlobal);
      if (focalView == null) return;

      final maxScale = controller.params.maxScale;
      final newZoom = (_pinchStartZoom! * (dist / _pinchStartDistance!))
          .clamp(controller.minScale, maxScale);

      final m = controller.value.clone();
      m.storage[0] = newZoom;
      m.storage[5] = newZoom;
      m.xZoomed = focalView.dx - _pinchStartFocalDoc!.dx * newZoom;
      m.yZoomed = focalView.dy - _pinchStartFocalDoc!.dy * newZoom;
      controller.value = m;
    }
  }

  void _applyPdfPanDelta(Offset delta) {
    final controller = widget.viewerController;
    if (controller == null || !controller.isReady) return;
    final m = controller.value.clone();
    m.xZoomed += delta.dx;
    m.yZoomed += delta.dy;
    controller.value = m;
  }

  void _handleNavEnd(int pointer, {bool allowFling = true}) {
    final tracker = _navVelocity.remove(pointer);
    _navPointers.remove(pointer);
    if (_navPointers.length < 2) {
      _clearPinch();
    }
    if (_navPointers.length == 2) {
      _beginPinchIfReady();
    }
    if (allowFling && _navPointers.isEmpty && !_navPinched) {
      final velocity = tracker?.getVelocity() ?? Velocity.zero;
      widget.panFling?.start(velocity.pixelsPerSecond);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    final tool = ref.read(activeToolProvider);
    if (tool == AnnotationTool.pan || _shouldNavigate(event.kind)) {
      _handleNavDown(event);
      return;
    }

    _handleDrawDown(event);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_navPointers.containsKey(event.pointer)) {
      _handleNavMove(event);
      return;
    }
    _handleDrawMove(event);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_navPointers.containsKey(event.pointer)) {
      _handleNavEnd(event.pointer);
      return;
    }
    _handleDrawUp(event);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_navPointers.containsKey(event.pointer)) {
      _handleNavEnd(event.pointer, allowFling: false);
      return;
    }
    _handleDrawCancel(event);
  }

  void _handleDrawDown(PointerDownEvent event) {
    final tool = ref.read(activeToolProvider);
    if (tool == AnnotationTool.pan) return;
    widget.panFling?.stop();

    _activePointer = event.pointer;
    _startPoint = event.localPosition;
    _layerSize = (context.findRenderObject() as RenderBox?)?.size ?? _layerSize;
    ref.read(currentInkPageProvider.notifier).state = widget.pageNumber;

    if (tool == AnnotationTool.eraser) {
      _eraseGestureActive = true;
      _eraserLast = event.localPosition;
      _eraserPreview.pos = event.localPosition;
      _eraserPreview.radius = _eraserRadius();
      _eraserPreview.mode = ref.read(penSettingsProvider).eraser;
      _eraseAt(event.localPosition, _layerSize);
      return;
    }

    if (tool == AnnotationTool.smelt) {
      _smeltDraft =
          Rect.fromPoints(event.localPosition, event.localPosition);
      ref.read(pdfSmeltRectProvider.notifier).state = _smeltDraft;
      setState(() {});
      return;
    }

    if (tool == AnnotationTool.pen || tool == AnnotationTool.highlighter) {
      _snapshotLiveStyle(tool);
      _livePoints
        ..clear()
        ..add(_makePoint(event.localPosition, event));
      ref.read(currentInkProvider.notifier).clear();
      _tickLiveInk();
    }
  }

  void _handleDrawMove(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    final tool = ref.read(activeToolProvider);

    if (tool == AnnotationTool.eraser) {
      final pos = event.localPosition;
      final radius = _eraserRadius();
      _eraserPreview.pos = pos;
      for (final sample in sampleErasePath(_eraserLast, pos, radius)) {
        _eraseAt(sample, _layerSize);
      }
      _eraserLast = pos;
      return;
    }

    if (tool == AnnotationTool.smelt && _startPoint != null) {
      _smeltDraft = Rect.fromPoints(_startPoint!, event.localPosition);
      ref.read(pdfSmeltRectProvider.notifier).state = _smeltDraft;
      setState(() {});
      return;
    }

    if (tool == AnnotationTool.pen || tool == AnnotationTool.highlighter) {
      appendInterpolated(
        _livePoints,
        [_makePoint(event.localPosition, event)],
      );
      _tickLiveInk();
    }
  }

  void _handleDrawUp(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    final tool = ref.read(activeToolProvider);
    final size = _layerSize;

    if (tool == AnnotationTool.eraser) {
      _eraseGestureActive = false;
      _eraserLast = null;
      _eraserPreview.pos = null;
      ref.read(currentInkPageProvider.notifier).state = null;
      return;
    }

    if (tool == AnnotationTool.smelt) {
      final rect = _smeltDraft?.normalize();
      _smeltDraft = null;
      if (rect != null) {
        ref.read(pdfSmeltRectProvider.notifier).state = rect;
        _offerSmelt(rect, size);
      } else {
        ref.read(pdfSmeltRectProvider.notifier).state = null;
      }
      ref.read(currentInkPageProvider.notifier).state = null;
      setState(() {});
      return;
    }

    if (tool == AnnotationTool.pen || tool == AnnotationTool.highlighter) {
      _saveCurrentStroke(size);
    }
  }

  void _handleDrawCancel(PointerEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _clearLiveInk();
    ref.read(currentInkProvider.notifier).clear();
    ref.read(currentInkPageProvider.notifier).state = null;
    ref.read(pdfSmeltRectProvider.notifier).state = null;
    _smeltDraft = null;
    _eraserLast = null;
    _eraseGestureActive = false;
    _eraserPreview.pos = null;
    _startPoint = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final activeTool = ref.watch(activeToolProvider);
    final annotationsAsync =
        ref.watch(pageAnnotationsProvider(widget.pageNumber));
    final penSettings = ref.watch(penSettingsProvider);
    final widthMod = ref.watch(strokeWidthModifierProvider);
    final stylusOnly = ref.watch(stylusOnlyModeProvider);
    final smeltRect = ref.watch(pdfSmeltRectProvider);
    final eraserRadius = eraserScreenRadius(widthMod);
    final showEraserPreview = activeTool == AnnotationTool.eraser;
    _eraserPreview.radius = eraserRadius;
    _eraserPreview.mode = penSettings.eraser;
    if (!showEraserPreview) {
      _eraserPreview.pos = null;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _layerSize = size;

        final paintLayer = Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: AnnotationPainter(
                annotations: annotationsAsync.value ?? [],
                streamline: penSettings.streamline,
                sensitivity: penSettings.sensitivityFor(_livePenStyle),
                smeltRect: smeltRect ?? _smeltDraft,
              ),
              size: size,
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: _PdfLiveInkPainter(
                  points: _livePoints,
                  color: _liveColor,
                  width: _liveWidth > 0
                      ? _liveWidth
                      : _strokeWidthFor(activeTool, mod: widthMod),
                  penStyle: _livePenStyle,
                  isHighlighter: _liveIsHighlighter,
                  streamline: penSettings.streamline,
                  sensitivity: penSettings.sensitivityFor(_livePenStyle),
                  tool: activeTool,
                  repaint: _liveTick,
                ),
                size: size,
              ),
            ),
            if (showEraserPreview)
              CustomPaint(
                painter: EraserPreviewPainter(
                  preview: _eraserPreview,
                  radius: eraserRadius,
                  mode: penSettings.eraser,
                ),
                size: size,
              ),
          ],
        );

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerHover: (event) {
            if (!showEraserPreview) return;
            if (stylusOnly && !_isStylus(event.kind)) return;
            if (_eraseGestureActive) return;
            _eraserPreview.pos = event.localPosition;
          },
          child: paintLayer,
        );
      },
    );
  }
}

extension on Rect {
  Rect normalize() {
    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }
}

class AnnotationPainter extends CustomPainter {
  final List<AnnotationRecord> annotations;
  final double streamline;
  final double sensitivity;
  final Rect? smeltRect;

  AnnotationPainter({
    required this.annotations,
    required this.streamline,
    required this.sensitivity,
    this.smeltRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final record in annotations) {
      if (record.type == AnnotationType.highlight ||
          record.data['isHighlighter'] == true) {
        _drawStroke(canvas, record, size);
      }
    }
    for (final record in annotations) {
      if (record.type == AnnotationType.comment) {
        _drawCommentMarker(canvas, record, size);
        continue;
      }
      if (record.type == AnnotationType.highlight ||
          record.data['isHighlighter'] == true) {
        continue;
      }
      _drawStroke(canvas, record, size);
    }

    final sel = smeltRect;
    if (sel != null) {
      final fill = Paint()
        ..color = const Color(0x332E6B5A)
        ..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = ScrapTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(sel, fill);
      canvas.drawRect(sel, stroke);
    }
  }

  void _drawCommentMarker(Canvas canvas, AnnotationRecord record, Size size) {
    final pts = _pointsOf(record, size);
    if (pts.isEmpty) return;
    canvas.drawCircle(
      Offset(pts.first.x, pts.first.y),
      6.0,
      Paint()
        ..color = const Color(0xFF6B4C3B)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawStroke(Canvas canvas, AnnotationRecord record, Size size) {
    final pts = _pointsOf(record, size);
    if (pts.isEmpty) return;

    final colorVal = record.data['color'] as int? ?? 0xFF1C1C1C;
    final strokeW = (record.data['strokeWidth'] as num?)?.toDouble() ?? 1.5;
    final isHL = record.type == AnnotationType.highlight ||
        record.data['isHighlighter'] == true;
    final styleName = record.data['penStyle'] as String?;
    final style = styleName != null
        ? PenStyle.values.firstWhere(
            (s) => s.name == styleName,
            orElse: () => PenStyle.pen,
          )
        : PenStyle.pen;

    InkRenderer.paint(
      canvas: canvas,
      pts: pts,
      color: Color(colorVal),
      baseWidth: strokeW,
      style: style,
      isHighlighter: isHL,
      streamline: streamline,
      sensitivity: sensitivity,
      isComplete: true,
      multiplyWithBackdrop: isHL,
    );
  }

  List<StrokePoint> _pointsOf(AnnotationRecord record, Size size) {
    final pointsList = record.data['points'] as List<dynamic>?;
    if (pointsList == null || pointsList.isEmpty) return const [];
    final normalized = record.data['normalized'] == true;
    return pointsList.map((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final nx = (m['x'] as num?)?.toDouble() ?? (m['dx'] as num).toDouble();
      final ny = (m['y'] as num?)?.toDouble() ?? (m['dy'] as num).toDouble();
      return StrokePoint(
        x: normalized ? nx * size.width : nx,
        y: normalized ? ny * size.height : ny,
        pressure: (m['pressure'] as num?)?.toDouble() ?? 1.0,
        timestamp: (m['timestamp'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) => true;
}

class _PdfLiveInkPainter extends CustomPainter {
  final List<StrokePoint> points;
  final Color color;
  final double width;
  final PenStyle penStyle;
  final bool isHighlighter;
  final double streamline;
  final double sensitivity;
  final AnnotationTool tool;

  _PdfLiveInkPainter({
    required this.points,
    required this.color,
    required this.width,
    required this.penStyle,
    required this.isHighlighter,
    required this.streamline,
    required this.sensitivity,
    required this.tool,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    if (tool != AnnotationTool.pen && tool != AnnotationTool.highlighter) {
      return;
    }
    final isHL = isHighlighter || tool == AnnotationTool.highlighter;
    InkRenderer.paint(
      canvas: canvas,
      pts: points,
      color: color,
      baseWidth: width,
      style: penStyle,
      isHighlighter: isHL,
      streamline: streamline,
      sensitivity: sensitivity,
      isComplete: false,
      multiplyWithBackdrop: isHL,
    );
  }

  @override
  bool shouldRepaint(covariant _PdfLiveInkPainter old) => true;
}
