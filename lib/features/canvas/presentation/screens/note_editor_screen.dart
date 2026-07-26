import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/smelt_popup.dart';
import '../providers/canvas_providers.dart';
import '../providers/smelt_detection_provider.dart';
import '../widgets/handwriting_canvas.dart';
import '../widgets/canvas_toolbar.dart';
import '../widgets/canvas_smart_widgets.dart';
import '../widgets/canvas_text_sticker.dart';
import '../widgets/document_tab_bar.dart';
import '../widgets/sticker_library.dart';
import '../../domain/models/stroke.dart';
import '../../data/canvas_ocr_service.dart';


// Provides OCR results dynamically over the canvas
final ocrResultsProvider = StateProvider<List<CanvasOcrResult>>((ref) => []);

class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final ScrollController _scrollController = ScrollController();
  final CanvasOcrService _ocrService = CanvasOcrService();

  Timer? _ocrDebounce;
  OverlayEntry? _smeltOverlayEntry;
  OverlayEntry? _smeltPopupEntry;
  final GlobalKey _canvasRepaintKey = GlobalKey();
  Offset? _lassoStart;
  Rect? _lassoPreviewRect;
  Rect? _selectionRect;
  Set<String> _selectedStrokeIds = {};
  bool _showSelectionMenu = false;
  bool _isResizingSelection = false;
  _CopiedSelection? _clipboardSelection;
  Offset? _pasteMenuAnchor;
  bool _showPasteMenu = false;
  String? _activeClusterId;
  bool _selectionFromDetection = false;
  bool _manualHintVisible = false;
  Offset? _manualSelectMenuAnchor;
  Timer? _manualHintTimer;
  int? _stylusSelectionPointerId;
  Offset? _stylusSelectionDownPos;
  bool _stylusSelectionDragStarted = false;

  static const double _selectionDragSlop = 8.0;

  bool _isStylusPointer(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  bool _isSelectionTool(CanvasTool tool) =>
      tool == CanvasTool.lasso || tool == CanvasTool.smelt;

  @override
  void initState() {
    super.initState();
    // Warm up background cluster detection without watching (no rebuilds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(detectedClustersProvider);
    });
  }

  void _triggerOcrRun() {
    _ocrDebounce?.cancel();
    _ocrDebounce = Timer(const Duration(milliseconds: 1500), () async {
      final strokes = ref.read(strokesProvider);
      final results = await _ocrService.recognizeStrokes(
          strokes, const BoxConstraints(maxWidth: 1000, maxHeight: 5000));
      ref.read(ocrResultsProvider.notifier).state = results;
    });
  }

  @override
  void dispose() {
    _ocrDebounce?.cancel();
    _manualHintTimer?.cancel();
    _ocrService.dispose();
    _scrollController.dispose();
    _smeltOverlayEntry?.remove();
    _smeltPopupEntry?.remove();
    super.dispose();
  }

  void _onCanvasTapDown(TapDownDetails details) {
    if (_selectionRect != null && !_selectionRect!.contains(details.localPosition)) {
      _clearSelectionState();
      _hidePasteMenu();
      return;
    }

    if (_showPasteMenu) {
      setState(() {
        _showPasteMenu = false;
        _pasteMenuAnchor = null;
      });
    }

    final tool = ref.read(activeCanvasToolProvider);
    if (_isSelectionTool(tool)) return;

    if (tool == CanvasTool.text) {
      final newText = CanvasTextItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        position: details.localPosition,
      );
      ref.read(canvasTextNodesProvider.notifier).update((s) => [...s, newText]);
      return;
    }

    if (tool != CanvasTool.pen) return;
  }

  bool _tapHitsManualSelectMenu(Offset p) {
    if (_manualSelectMenuAnchor == null) return false;
    final left = math.max(_manualSelectMenuAnchor!.dx, 12.0);
    final top = math.max(_manualSelectMenuAnchor!.dy - 52, 12.0);
    const menuWidth = 148.0;
    const menuHeight = 48.0;
    return Rect.fromLTWH(left, top, menuWidth, menuHeight).contains(p);
  }

  void _onCanvasTapUp(TapUpDetails details) {
    if (ref.read(activeCanvasToolProvider) != CanvasTool.smelt) return;
    if (ref.read(stylusOnlyModeProvider)) return;
    if (_lassoStart != null || _lassoPreviewRect != null) return;
    if (_tapHitsManualSelectMenu(details.localPosition)) return;
    _handleSmeltTapAt(details.localPosition);
  }

  void _handleSmeltTapAt(Offset position) {
    if (_tapHitsManualSelectMenu(position)) return;

    final cluster = ref
        .read(detectedClustersProvider.notifier)
        .hitTest(position);

    if (cluster == null) {
      if (ref.read(stylusOnlyModeProvider)) return;

      _hidePasteMenu();
      setState(() {
        _selectionRect = null;
        _selectedStrokeIds = {};
        _activeClusterId = null;
        _selectionFromDetection = false;
        _showSelectionMenu = false;
        _manualSelectMenuAnchor = position;
      });
      return;
    }

    _hidePasteMenu();
    setState(() {
      _selectionRect = cluster.bounds;
      _selectedStrokeIds = Set<String>.from(cluster.strokeIds);
      _activeClusterId = cluster.id;
      _selectionFromDetection = true;
      _showSelectionMenu = true;
      _isResizingSelection = false;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });
  }

  void _onSelectionPointerDown(PointerDownEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (!_isSelectionTool(ref.read(activeCanvasToolProvider))) return;
    if (!_isStylusPointer(event.kind)) return;

    _stylusSelectionPointerId = event.pointer;
    _stylusSelectionDownPos = event.localPosition;
    _stylusSelectionDragStarted = false;
  }

  void _onSelectionPointerMove(PointerMoveEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (_stylusSelectionPointerId != event.pointer) return;
    if (_stylusSelectionDownPos == null) return;

    if (!_stylusSelectionDragStarted) {
      if ((event.localPosition - _stylusSelectionDownPos!).distance <
          _selectionDragSlop) {
        return;
      }
      _stylusSelectionDragStarted = true;
      _startLassoAt(_stylusSelectionDownPos!);
    }

    if (_lassoStart != null) {
      _updateLassoTo(event.localPosition);
    }
  }

  void _onSelectionPointerUp(PointerUpEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (_stylusSelectionPointerId != event.pointer) return;

    if (_stylusSelectionDragStarted && _lassoStart != null) {
      _finishLassoGesture();
    } else if (!_stylusSelectionDragStarted &&
        ref.read(activeCanvasToolProvider) == CanvasTool.smelt &&
        _isStylusPointer(event.kind)) {
      _handleSmeltTapAt(event.localPosition);
    }

    _resetStylusSelectionPointer();
  }

  void _onSelectionPointerCancel(PointerCancelEvent event) {
    if (_stylusSelectionPointerId != event.pointer) return;
    _resetStylusSelectionPointer();
    if (_lassoStart != null) {
      setState(() {
        _lassoStart = null;
        _lassoPreviewRect = null;
      });
    }
  }

  void _resetStylusSelectionPointer() {
    _stylusSelectionPointerId = null;
    _stylusSelectionDownPos = null;
    _stylusSelectionDragStarted = false;
  }

  void _startLasso(DragStartDetails details) {
    if (!_isSelectionTool(ref.read(activeCanvasToolProvider))) return;
    if (ref.read(stylusOnlyModeProvider)) return;
    _startLassoAt(details.localPosition);
  }

  void _startLassoAt(Offset position) {
    if (!_isSelectionTool(ref.read(activeCanvasToolProvider))) return;
    _hideSelectionMenu();
    setState(() {
      _lassoStart = position;
      _lassoPreviewRect = Rect.fromPoints(position, position);
      _selectionFromDetection = false;
      _activeClusterId = null;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });
  }

  void _updateLasso(DragUpdateDetails details) {
    if (ref.read(stylusOnlyModeProvider)) return;
    _updateLassoTo(details.localPosition);
  }

  void _updateLassoTo(Offset position) {
    if (_lassoStart == null || !_isSelectionTool(ref.read(activeCanvasToolProvider))) {
      return;
    }

    final draggedRect = _normalizedRect(Rect.fromPoints(_lassoStart!, position));
    final strokes = ref.read(strokesProvider);
    final selected = strokes
        .where((stroke) => !stroke.isHidden && _strokeIntersectsSelection(stroke, draggedRect))
        .toList();

    setState(() {
      _lassoPreviewRect = draggedRect;
      _selectionRect = selected.isEmpty
          ? null
          : _unionRects(selected.map((stroke) => _strokeBounds(stroke).inflate(4)).toList());
      _selectedStrokeIds = selected.map((stroke) => stroke.id).toSet();
      _showSelectionMenu = false;
      _selectionFromDetection = false;
    });
  }

  void _endLasso(DragEndDetails details) {
    if (ref.read(stylusOnlyModeProvider)) return;
    _finishLassoGesture();
  }

  void _finishLassoGesture() {
    if (_lassoStart == null) return;

    if (_selectionRect == null || _selectedStrokeIds.isEmpty) {
      setState(() {
        _lassoStart = null;
        _lassoPreviewRect = null;
        _selectionRect = null;
        _selectedStrokeIds = {};
        _showSelectionMenu = false;
        _selectionFromDetection = false;
        _activeClusterId = null;
      });
      return;
    }

    setState(() {
      _selectionFromDetection = false;
      _activeClusterId = null;
    });
    _refreshSelectionBounds(showMenu: true);
    _hidePasteMenu();

    setState(() {
      _lassoStart = null;
      _lassoPreviewRect = null;
    });
  }

  void _hideSelectionMenu() {
    if (!_showSelectionMenu && !_isResizingSelection) return;
    setState(() {
      _showSelectionMenu = false;
    });
  }

  void _clearSelectionState() {
    if (_selectionRect == null &&
        _selectedStrokeIds.isEmpty &&
        !_showSelectionMenu &&
        !_isResizingSelection &&
        _activeClusterId == null &&
        !_selectionFromDetection &&
        _manualSelectMenuAnchor == null) {
      return;
    }

    setState(() {
      _lassoStart = null;
      _lassoPreviewRect = null;
      _selectionRect = null;
      _selectedStrokeIds = {};
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _activeClusterId = null;
      _selectionFromDetection = false;
      _manualSelectMenuAnchor = null;
    });
  }

  void _beginManualSelect() {
    _manualHintTimer?.cancel();
    setState(() {
      _lassoStart = null;
      _lassoPreviewRect = null;
      _selectionRect = null;
      _selectedStrokeIds = {};
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _activeClusterId = null;
      _selectionFromDetection = false;
      _manualSelectMenuAnchor = null;
      _manualHintVisible = true;
    });
    _manualHintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _manualHintVisible = false);
    });
  }

  void _hidePasteMenu() {
    if (!_showPasteMenu) return;
    setState(() {
      _showPasteMenu = false;
      _pasteMenuAnchor = null;
    });
  }

  Rect _unionRects(List<Rect> rects) {
    if (rects.isEmpty) return Rect.zero;

    var left = rects.first.left;
    var top = rects.first.top;
    var right = rects.first.right;
    var bottom = rects.first.bottom;

    for (final rect in rects.skip(1)) {
      if (rect.left < left) left = rect.left;
      if (rect.top < top) top = rect.top;
      if (rect.right > right) right = rect.right;
      if (rect.bottom > bottom) bottom = rect.bottom;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _strokeBounds(Stroke stroke) {
    if (stroke.points.isEmpty) return Rect.zero;

    double minX = stroke.points.first.x;
    double maxX = stroke.points.first.x;
    double minY = stroke.points.first.y;
    double maxY = stroke.points.first.y;

    for (final point in stroke.points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _strokeIntersectsSelection(Stroke stroke, Rect selection) {
    for (final point in stroke.points) {
      if (selection.contains(Offset(point.x, point.y))) return true;
    }

    for (var i = 1; i < stroke.points.length; i++) {
      final previous = Offset(stroke.points[i - 1].x, stroke.points[i - 1].y);
      final current = Offset(stroke.points[i].x, stroke.points[i].y);
      if (_segmentIntersectsRect(previous, current, selection)) return true;
    }

    return false;
  }

  bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    if (rect.contains(a) || rect.contains(b)) return true;

    final rectPoints = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];

    for (var i = 0; i < rectPoints.length; i++) {
      final start = rectPoints[i];
      final end = rectPoints[(i + 1) % rectPoints.length];
      if (_segmentsIntersect(a, b, start, end)) return true;
    }

    return false;
  }

  bool _segmentsIntersect(Offset a1, Offset a2, Offset b1, Offset b2) {
    double direction(Offset p1, Offset p2, Offset p3) {
      return (p3.dx - p1.dx) * (p2.dy - p1.dy) - (p2.dx - p1.dx) * (p3.dy - p1.dy);
    }

    bool onSegment(Offset p1, Offset p2, Offset p3) {
      return p2.dx >= math.min(p1.dx, p3.dx) &&
          p2.dx <= math.max(p1.dx, p3.dx) &&
          p2.dy >= math.min(p1.dy, p3.dy) &&
          p2.dy <= math.max(p1.dy, p3.dy);
    }

    final d1 = direction(a1, a2, b1);
    final d2 = direction(a1, a2, b2);
    final d3 = direction(b1, b2, a1);
    final d4 = direction(b1, b2, a2);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }

    if (d1 == 0 && onSegment(a1, b1, a2)) return true;
    if (d2 == 0 && onSegment(a1, b2, a2)) return true;
    if (d3 == 0 && onSegment(b1, a1, b2)) return true;
    if (d4 == 0 && onSegment(b1, a2, b2)) return true;

    return false;
  }

  void _moveSelection(Offset delta) {
    if (_selectionRect == null) return;
    if (_selectedStrokeIds.isEmpty) return;

    _hideSelectionMenu();
    _hidePasteMenu();

    final strokes = ref.read(strokesProvider);
    final movedStrokes = <Stroke>[];

    for (final stroke in strokes) {
      if (_selectedStrokeIds.contains(stroke.id)) {
        movedStrokes.add(_translateStroke(stroke, delta));
      }
    }

    ref.read(strokesProvider.notifier).updateStrokes(movedStrokes);
    setState(() {
      _selectionRect = _selectionRect!.shift(delta);
    });
  }

  void _finishSelectionMove() {
    if (_selectionRect == null) return;
    _refreshSelectionBounds(showMenu: true);
  }

  void _beginResizeSelection() {
    if (_selectionRect == null) return;
    setState(() {
      _isResizingSelection = true;
      _showSelectionMenu = false;
      _showPasteMenu = false;
      _pasteMenuAnchor = null;
    });
  }

  void _resizeSelection(int cornerIndex, Offset delta) {
    if (_selectionRect == null) return;
    if (_selectedStrokeIds.isEmpty) return;

    final oldRect = _selectionRect!;
    Rect updated;
    switch (cornerIndex) {
      case 0:
        updated = Rect.fromLTRB(oldRect.left + delta.dx, oldRect.top + delta.dy, oldRect.right, oldRect.bottom);
        break;
      case 1:
        updated = Rect.fromLTRB(oldRect.left, oldRect.top + delta.dy, oldRect.right + delta.dx, oldRect.bottom);
        break;
      case 2:
        updated = Rect.fromLTRB(oldRect.left + delta.dx, oldRect.top, oldRect.right, oldRect.bottom + delta.dy);
        break;
      case 3:
      default:
        updated = Rect.fromLTRB(oldRect.left, oldRect.top, oldRect.right + delta.dx, oldRect.bottom + delta.dy);
        break;
    }

    if (updated.width < 20 || updated.height < 20) return;

    final scaleX = updated.width / oldRect.width;
    final scaleY = updated.height / oldRect.height;
    final strokes = ref.read(strokesProvider);
    final transformed = <Stroke>[];

    for (final stroke in strokes) {
      if (_selectedStrokeIds.contains(stroke.id)) {
        transformed.add(_scaleStroke(stroke, oldRect, updated, scaleX, scaleY));
      }
    }

    ref.read(strokesProvider.notifier).updateStrokes(transformed);
    setState(() {
      _selectionRect = updated;
    });
  }

  void _finishResizeSelection() {
    if (_selectionRect == null) return;
    _refreshSelectionBounds(showMenu: true);
  }

  void _smeltSelection() async {
    if (_selectionRect == null || _selectedStrokeIds.isEmpty) return;
    _hideSelectionMenu();

    final rect = _selectionRect!;
    
    // Convert canvas-local coordinates to global screen coordinates
    // Account for the scroll offset and the canvas position within the scaffold
    final globalRect = _convertToGlobalRect(rect);

    // Show thinking overlay on the bounding box
    _smeltOverlayEntry?.remove();
    _smeltOverlayEntry = OverlayEntry(
      builder: (context) => SmeltThinkingOverlay(selectionRect: globalRect),
    );
    Overlay.of(context).insert(_smeltOverlayEntry!);

    // Start loading state
    ref.read(smeltProvider.notifier).startLoading();

    // Capture the canvas region as an image
    Uint8List? imageBytes;
    try {
      imageBytes = await _captureCanvasRegion(rect);
    } catch (_) {
      // If capture fails, fall back to null (text-only mode)
    }

    // Send to AI
    await ref.read(smeltProvider.notifier).smelt(imageBytes: imageBytes);

    // Remove thinking overlay
    _smeltOverlayEntry?.remove();
    _smeltOverlayEntry = null;

    // Show result popup
    if (mounted) {
      _showSmeltPopup(rect);
    }
  }

  Future<Uint8List?> _captureCanvasRegion(Rect region) async {
    final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final pixelRatio = 2.0;
    final image = await boundary.toImage(pixelRatio: pixelRatio);

    // Calculate crop rect in image pixel coordinates
    final cropRect = Rect.fromLTWH(
      region.left * pixelRatio,
      region.top * pixelRatio,
      region.width * pixelRatio,
      region.height * pixelRatio,
    );

    // Clamp crop rect to image bounds
    final clampedCropRect = Rect.fromLTWH(
      cropRect.left.clamp(0.0, image.width.toDouble()).toDouble(),
      cropRect.top.clamp(0.0, image.height.toDouble()).toDouble(),
      math.min(cropRect.width, image.width - cropRect.left).round().toDouble(),
      math.min(cropRect.height, image.height - cropRect.top).round().toDouble(),
    );

    // Create cropped image using PictureRecorder
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Draw only the cropped portion from source to destination
    canvas.drawImageRect(
      image,
      clampedCropRect,
      Rect.fromLTWH(0, 0, clampedCropRect.width, clampedCropRect.height),
      ui.Paint(),
    );

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(
      clampedCropRect.width.round(),
      clampedCropRect.height.round(),
    );

    final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    croppedImage.dispose();

    if (byteData == null) return null;

    Uint8List bytes = byteData.buffer.asUint8List();

    // Compress if larger than 1MB
    if (bytes.length > 1024 * 1024) {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: (clampedCropRect.width * 0.5).round(),
      );
      final frame = await codec.getNextFrame();
      final compressed = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (compressed != null) {
        bytes = compressed.buffer.asUint8List();
      }
    }

    return bytes;
  }

  /// Convert canvas-local rect to global screen coordinates
  Rect _convertToGlobalRect(Rect localRect) {
    // Get the scroll offset
    final scrollOffset = _scrollController.offset;
    
    // Get the canvas position on screen
    final renderBox = _canvasRepaintKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return localRect;
    
    // Get the global position of the canvas origin
    final globalOffset = renderBox.localToGlobal(Offset.zero);
    
    // Convert: globalY = localY - scrollOffset + canvasGlobalY
    // The scroll offset shifts content up, so we subtract it
    return localRect.translate(
      globalOffset.dx,
      globalOffset.dy - scrollOffset,
    );
  }

  void _showSmeltPopup(Rect selectionRect) {
    _smeltPopupEntry?.remove();
    
    // Convert to global coordinates for the popup positioning
    final globalRect = _convertToGlobalRect(selectionRect);

    _smeltPopupEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Tap outside to dismiss
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismissSmeltPopup,
              child: const SizedBox.expand(),
            ),
          ),
          SmeltPopup(
            selectionRect: globalRect,
            onDismiss: _dismissSmeltPopup,
            screenSize: MediaQuery.of(context).size,
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_smeltPopupEntry!);
  }

  void _dismissSmeltPopup() {
    _smeltPopupEntry?.remove();
    _smeltPopupEntry = null;
    ref.read(smeltProvider.notifier).clearState();
  }

  void _deleteSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _hideSelectionMenu();
    ref.read(strokesProvider.notifier).deleteStrokes(_selectedStrokeIds.toList());
    setState(() {
      _selectionRect = null;
      _selectedStrokeIds = {};
      _isResizingSelection = false;
      _showSelectionMenu = false;
    });
  }

  void _copySelection() async {
    if (_selectionRect == null || _selectedStrokeIds.isEmpty) return;
    _hideSelectionMenu();
    await Clipboard.setData(const ClipboardData(text: 'Scrapyard selection copied'));
    final strokes = ref.read(strokesProvider);
    final copied = strokes
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .map((stroke) => _cloneStroke(stroke))
        .toList();
    setState(() {
      _clipboardSelection = _CopiedSelection(
        strokes: copied,
        bounds: _selectionRect!,
      );
      _showSelectionMenu = false;
    });
  }

  void _showPasteMenuAt(Offset position) {
    if (_clipboardSelection == null) return;
    setState(() {
      _pasteMenuAnchor = position;
      _showPasteMenu = true;
      _showSelectionMenu = false;
    });
  }

  void _pasteClipboard(Offset position) {
    final clipboard = _clipboardSelection;
    if (clipboard == null) return;

    final delta = position - clipboard.bounds.center;
    final notifier = ref.read(strokesProvider.notifier);
    for (final stroke in clipboard.strokes) {
      notifier.addStroke(_cloneStroke(stroke, offset: delta));
    }

    _hidePasteMenu();
  }

  Stroke _cloneStroke(Stroke stroke, {Offset offset = Offset.zero}) {
    return Stroke(
      id: DateTime.now().microsecondsSinceEpoch.toString() + stroke.id,
      points: stroke.points
          .map((point) => StrokePoint(
                x: point.x + offset.dx,
                y: point.y + offset.dy,
                pressure: point.pressure,
                timestamp: point.timestamp,
              ))
          .toList(),
      color: stroke.color,
      baseWidth: stroke.baseWidth,
      isBrush: stroke.isBrush,
      isHighlighter: stroke.isHighlighter,
      isTape: stroke.isTape,
      isHidden: stroke.isHidden,
      isStraightLine: stroke.isStraightLine,
      style: stroke.style,
      shapeType: stroke.shapeType,
      shapeVertices: stroke.shapeVertices,
      isBeautified: stroke.isBeautified,
      penStyle: stroke.penStyle,
    );
  }

  Stroke _translateStroke(Stroke stroke, Offset delta) {
    return Stroke(
      id: stroke.id,
      points: stroke.points
          .map((point) => StrokePoint(
                x: point.x + delta.dx,
                y: point.y + delta.dy,
                pressure: point.pressure,
                timestamp: point.timestamp,
              ))
          .toList(),
      color: stroke.color,
      baseWidth: stroke.baseWidth,
      isBrush: stroke.isBrush,
      isHighlighter: stroke.isHighlighter,
      isTape: stroke.isTape,
      isHidden: stroke.isHidden,
      isStraightLine: stroke.isStraightLine,
      style: stroke.style,
      shapeType: stroke.shapeType,
      shapeVertices: _translateVertices(stroke.shapeVertices, delta),
      isBeautified: stroke.isBeautified,
      penStyle: stroke.penStyle,
    );
  }

  Stroke _scaleStroke(Stroke stroke, Rect from, Rect to, double scaleX, double scaleY) {
    return Stroke(
      id: stroke.id,
      points: stroke.points
          .map((point) => StrokePoint(
                x: to.left + ((point.x - from.left) * scaleX),
                y: to.top + ((point.y - from.top) * scaleY),
                pressure: point.pressure,
                timestamp: point.timestamp,
              ))
          .toList(),
      color: stroke.color,
      baseWidth: stroke.baseWidth,
      isBrush: stroke.isBrush,
      isHighlighter: stroke.isHighlighter,
      isTape: stroke.isTape,
      isHidden: stroke.isHidden,
      isStraightLine: stroke.isStraightLine,
      style: stroke.style,
      shapeType: stroke.shapeType,
      shapeVertices: _scaleVertices(stroke.shapeVertices, from, to, scaleX, scaleY),
      isBeautified: stroke.isBeautified,
      penStyle: stroke.penStyle,
    );
  }

  List<double> _translateVertices(List<double> vertices, Offset delta) {
    if (vertices.isEmpty) return vertices;
    final translated = <double>[];
    for (var i = 0; i < vertices.length; i += 2) {
      translated.add(vertices[i] + delta.dx);
      translated.add(vertices[i + 1] + delta.dy);
    }
    return translated;
  }

  List<double> _scaleVertices(List<double> vertices, Rect from, Rect to, double scaleX, double scaleY) {
    if (vertices.isEmpty) return vertices;
    final scaled = <double>[];
    for (var i = 0; i < vertices.length; i += 2) {
      final x = vertices[i];
      final y = vertices[i + 1];
      scaled.add(to.left + ((x - from.left) * scaleX));
      scaled.add(to.top + ((y - from.top) * scaleY));
    }
    return scaled;
  }

  void _refreshSelectionBounds({required bool showMenu}) {
    if (_selectedStrokeIds.isEmpty) {
      setState(() {
        _selectionRect = null;
        _showSelectionMenu = false;
        _isResizingSelection = false;
      });
      return;
    }

    final strokes = ref.read(strokesProvider);
    final selected = strokes.where((stroke) => _selectedStrokeIds.contains(stroke.id)).toList();
    if (selected.isEmpty) {
      setState(() {
        _selectionRect = null;
        _selectedStrokeIds = {};
        _showSelectionMenu = false;
        _isResizingSelection = false;
      });
      return;
    }

    final bounds = _unionRects(selected.map((stroke) => _strokeBounds(stroke).inflate(4)).toList());
    setState(() {
      _selectionRect = bounds;
      _showSelectionMenu = showMenu;
      _isResizingSelection = false;
    });
  }

  void _handleCanvasLongPressStart(LongPressStartDetails details) {
    if (_clipboardSelection == null) return;
    _showPasteMenuAt(details.localPosition);
  }

  Rect _normalizedRect(Rect rect) {
    return Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(strokesProvider, (previous, next) {
      if (previous != null && next.length > previous.length) _triggerOcrRun();
    });

    ref.listen<CanvasTool>(activeCanvasToolProvider, (previous, next) {
      if (previous != next && next != CanvasTool.lasso && next != CanvasTool.smelt) {
        _clearSelectionState();
        _hidePasteMenu();
        _manualHintTimer?.cancel();
        if (_manualHintVisible) setState(() => _manualHintVisible = false);
        if (_manualSelectMenuAnchor != null) setState(() => _manualSelectMenuAnchor = null);
      }
    });

    ref.listen<bool>(stylusOnlyModeProvider, (previous, next) {
      if (next && mounted) {
        _manualHintTimer?.cancel();
        _resetStylusSelectionPointer();
        setState(() {
          _lassoStart = null;
          _lassoPreviewRect = null;
          _manualHintVisible = false;
          _manualSelectMenuAnchor = null;
        });
      }
    });

    final isPenMode       = ref.watch(isPenModeActiveProvider);
    final stylusOnly      = ref.watch(stylusOnlyModeProvider);
    final activeTool      = ref.watch(activeCanvasToolProvider);
    final isLassoMode     = activeTool == CanvasTool.lasso;
    final isSmeltMode     = activeTool == CanvasTool.smelt;
    final isSelectionMode = isLassoMode || isSmeltMode;
    final allowSelectionDrag = isSelectionMode && !stylusOnly;
    final canvasZoom      = ref.watch(canvasZoomProvider);
    final toolbarPosition = ref.watch(toolbarPositionProvider);

    final canvasStack = RepaintBoundary(
      key: _canvasRepaintKey,
      child: Stack(
        children: [
          HandwritingCanvas(
            scrollController: _scrollController,
            zoomLevel: canvasZoom,
            onZoomChanged: (v) => ref.read(canvasZoomProvider.notifier).state = v,
          ),
          // Transparent text annotations — tap to edit, drag to move
          ...ref.watch(canvasTextNodesProvider)
              .map((node) => CanvasTextSticker(key: ValueKey(node.id), item: node)),
          // Emoji / decorative stickers
          ...ref.watch(canvasStickersProvider)
              .map((s) => CanvasStickerOverlay(key: ValueKey(s.id), sticker: s)),
          // Table overlays
          ...ref.watch(canvasTablesProvider)
              .map((t) => CanvasTableOverlay(table: t)),
        ],
      ),
    );

    // Lasso/selection/paste overlays live inside the transform so they stay
    // in logical coordinates (matching stroke positions).
    final List<Widget> contentOverlays = [];
    if (_lassoPreviewRect != null) {
      contentOverlays.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LassoPainter(_lassoPreviewRect!),
            ),
          ),
        ),
      );
    }
    if (_selectionRect != null) {
      contentOverlays.add(
        Positioned.fill(
          child: Stack(
            children: [
              if (_selectionFromDetection)
                TweenAnimationBuilder<double>(
                  key: ValueKey(_activeClusterId ?? 'detected'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 160),
                  builder: (context, value, child) =>
                      Opacity(opacity: value, child: child),
                  child: CustomPaint(
                    painter: _DetectedBoxPainter(_selectionRect!),
                  ),
                )
              else
                CustomPaint(
                  painter: _SelectedStrokeHighlightPainter(_selectionRect!),
                ),
              if (!_isResizingSelection)
                Positioned.fromRect(
                  rect: _selectionRect!,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) {
                      _hideSelectionMenu();
                      _hidePasteMenu();
                    },
                    onPanUpdate: (details) => _moveSelection(details.delta),
                    onPanEnd: (_) => _finishSelectionMove(),
                    child: const SizedBox.expand(),
                  ),
                ),
              if (_isResizingSelection) ...[
                _SelectionCornerHandle(
                  rect: _selectionRect!,
                  cornerIndex: 0,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(0, delta),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: _selectionRect!,
                  cornerIndex: 1,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(1, delta),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: _selectionRect!,
                  cornerIndex: 2,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(2, delta),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: _selectionRect!,
                  cornerIndex: 3,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(3, delta),
                  onPanEnd: _finishResizeSelection,
                ),
              ],
              if (_showSelectionMenu && isSmeltMode)
                _SmeltActionMenu(
                  rect: _selectionRect!,
                  showManualSelect: _selectionFromDetection,
                  onSmelt: _smeltSelection,
                  onManualSelect: _beginManualSelect,
                )
              else if (_showSelectionMenu && !isSmeltMode)
                _SelectionActionMenu(
                  rect: _selectionRect!,
                  onResize: _beginResizeSelection,
                  onDelete: _deleteSelection,
                  onCopy: _copySelection,
                ),
            ],
          ),
        ),
      );
    }
    if (_manualHintVisible && isSmeltMode && !stylusOnly) {
      contentOverlays.add(
        Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KotoTheme.dividers),
                  boxShadow: KotoTheme.subtleShadow,
                ),
                child: Text(
                  'Drag to select',
                  style: KotoTextStyles.caption.copyWith(
                    color: KotoTheme.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (_manualSelectMenuAnchor != null && isSmeltMode && !stylusOnly) {
      contentOverlays.add(
        Positioned(
          left: math.max(_manualSelectMenuAnchor!.dx, 12.0),
          top: math.max(_manualSelectMenuAnchor!.dy - 52, 12.0),
          child: _ManualSelectActionMenu(onSelect: _beginManualSelect),
        ),
      );
    }
    if (_showPasteMenu && _pasteMenuAnchor != null) {
      contentOverlays.add(
        Positioned(
          left: _pasteMenuAnchor!.dx,
          top: _pasteMenuAnchor!.dy,
          child: _PasteMenu(
            onPaste: () => _pasteClipboard(_pasteMenuAnchor!),
          ),
        ),
      );
    }

    final canvasSurface = Expanded(
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            // In pen mode (or lasso), the HandwritingCanvas Listener handles all
            // pointer events — the scroll view must not compete.  When stylus-only
            // is on, the canvas also handles touch scrolling manually via jumpTo(),
            // so the scroll view must stay out of the way.
            physics: (isSelectionMode || isPenMode)
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: ColoredBox(
              color: canvasZoom <= 1.0
                  ? KotoTheme.cardSurface
                  : KotoTheme.background,
              child: SizedBox(
                width: double.infinity,
                height: 5000 * canvasZoom,
                child: Transform.scale(
                  scale: canvasZoom,
                  alignment: canvasZoom <= 1.0
                      ? const Alignment(0, -1)
                      : Alignment.topLeft,
                  child: SizedBox(
                    width: double.infinity,
                    height: 5000,
                    child: Listener(
                      onPointerDown: stylusOnly && isSelectionMode
                          ? _onSelectionPointerDown
                          : null,
                      onPointerMove: stylusOnly && isSelectionMode
                          ? _onSelectionPointerMove
                          : null,
                      onPointerUp: stylusOnly && isSelectionMode
                          ? _onSelectionPointerUp
                          : null,
                      onPointerCancel: stylusOnly && isSelectionMode
                          ? _onSelectionPointerCancel
                          : null,
                      child: GestureDetector(
                        onTapDown: _onCanvasTapDown,
                        onTapUp: isSmeltMode ? _onCanvasTapUp : null,
                        onLongPressStart: _handleCanvasLongPressStart,
                        onPanStart: allowSelectionDrag ? _startLasso : null,
                        onPanUpdate: allowSelectionDrag ? _updateLasso : null,
                        onPanEnd: allowSelectionDrag ? _endLasso : null,
                        child: Stack(
                          children: [
                            canvasStack,
                            ...contentOverlays,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Smart action FAB — bottom right, always on screen
          Positioned(
            right: 16, bottom: 16,
            child: CanvasSmartBar(
              ocrTexts: ref.watch(ocrResultsProvider).map((r) => r.text).toList(),
              ocrStrokeIds: const [],
            ),
          ),
        ],
      ),
    );

    Widget toolSurface;
    switch (toolbarPosition) {
      case ToolbarPosition.top:
        toolSurface = Column(children: [
          // Removed SafeArea entirely
          const CanvasToolbar(), 
          Expanded(child: canvasSurface),
        ]);
        break;
      case ToolbarPosition.bottom:
        toolSurface = Column(children: [
          canvasSurface,
          const SafeArea(top: false, child: CanvasToolbar()),
        ]);
        break;
      case ToolbarPosition.left:
        toolSurface = SafeArea(child: Row(children: [const CanvasToolbar(), canvasSurface]));
        break;
      case ToolbarPosition.right:
        toolSurface = SafeArea(child: Row(children: [canvasSurface, const CanvasToolbar()]));
        break;
    }

    return Scaffold(
      backgroundColor: KotoTheme.background,
      body: Column(
        children: [
          const SafeArea(bottom: false, child: DocumentTabBar()),
          Expanded(child: toolSurface),
        ],
      ),
    );
  }
}

class _LassoPainter extends CustomPainter {
  final Rect rect;

  _LassoPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = KotoTheme.accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = KotoTheme.accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => oldDelegate.rect != rect;
}

class _SelectedStrokeHighlightPainter extends CustomPainter {
  final Rect rect;

  _SelectedStrokeHighlightPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7AA7D8).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    _drawDashedRect(canvas, rect, paint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;

    void drawDashedLine(Offset start, Offset end) {
      final totalLength = (end - start).distance;
      if (totalLength == 0) return;

      final direction = (end - start) / totalLength;
      double distance = 0;
      while (distance < totalLength) {
        final from = start + direction * distance;
        final to = start + direction * math.min(distance + dashLength, totalLength);
        canvas.drawLine(from, to, paint);
        distance += dashLength + gapLength;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _SelectedStrokeHighlightPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _DetectedBoxPainter extends CustomPainter {
  final Rect rect;

  _DetectedBoxPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final fill = Paint()
      ..color = KotoTheme.accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = KotoTheme.accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, border);
  }

  @override
  bool shouldRepaint(covariant _DetectedBoxPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CopiedSelection {
  final List<Stroke> strokes;
  final Rect bounds;

  const _CopiedSelection({required this.strokes, required this.bounds});
}

class _SelectionActionMenu extends StatelessWidget {
  final Rect rect;
  final VoidCallback onResize;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  const _SelectionActionMenu({
    required this.rect,
    required this.onResize,
    required this.onDelete,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final top = math.max(rect.top - 64, 12.0);
    final left = math.max(rect.left, 12.0);

    return Positioned(
      top: top,
      left: left,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KotoTheme.dividers),
            boxShadow: KotoTheme.subtleShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuButton(label: 'Resize', onTap: onResize),
              const SizedBox(width: 8),
              _MenuButton(label: 'Delete', onTap: onDelete, danger: true),
              const SizedBox(width: 8),
              _MenuButton(label: 'Copy', onTap: onCopy),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmeltActionMenu extends StatelessWidget {
  final Rect rect;
  final bool showManualSelect;
  final VoidCallback onSmelt;
  final VoidCallback onManualSelect;

  const _SmeltActionMenu({
    required this.rect,
    required this.showManualSelect,
    required this.onSmelt,
    required this.onManualSelect,
  });

  @override
  Widget build(BuildContext context) {
    final top = math.max(rect.top - 64, 12.0);
    final left = math.max(rect.left, 12.0);

    return Positioned(
      top: top,
      left: left,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KotoTheme.dividers),
            boxShadow: KotoTheme.subtleShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmeltPillButton(onTap: onSmelt),
              if (showManualSelect) ...[
                const SizedBox(width: 8),
                _ManualSelectButton(onTap: onManualSelect),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSelectActionMenu extends StatelessWidget {
  final VoidCallback onSelect;

  const _ManualSelectActionMenu({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: KotoTheme.dividers),
          boxShadow: KotoTheme.subtleShadow,
        ),
        child: _ManualSelectButton(onTap: onSelect),
      ),
    );
  }
}

class _ManualSelectButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ManualSelectButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: KotoTheme.dividers),
        ),
        child: Text(
          'Select manually',
          style: KotoTextStyles.caption.copyWith(
            color: KotoTheme.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SmeltPillButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SmeltPillButton({required this.onTap});

  @override
  State<_SmeltPillButton> createState() => _SmeltPillButtonState();
}

class _SmeltPillButtonState extends State<_SmeltPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [KotoTheme.accent, Color(0xFF8A6A55)],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: KotoTheme.accent.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Smelt',
                style: KotoTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _MenuButton({required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFF7E6E6) : const Color(0xFFF5F1EC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: KotoTextStyles.caption.copyWith(
            color: danger ? const Color(0xFFB84444) : KotoTheme.primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PasteMenu extends StatelessWidget {
  final VoidCallback onPaste;

  const _PasteMenu({required this.onPaste});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onPaste,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: KotoTheme.dividers),
            boxShadow: KotoTheme.subtleShadow,
          ),
          child: Text(
            'Paste',
            style: KotoTextStyles.caption.copyWith(
              color: KotoTheme.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionCornerHandle extends StatelessWidget {
  final Rect rect;
  final int cornerIndex;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  const _SelectionCornerHandle({
    required this.rect,
    required this.cornerIndex,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final offsets = [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight];
    final position = offsets[cornerIndex];

    return Positioned(
      left: position.dx - 7,
      top: position.dy - 7,
      child: GestureDetector(
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) => onPanUpdate(details.delta),
        onPanEnd: (_) => onPanEnd(),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: KotoTheme.accent, width: 1.5),
            boxShadow: KotoTheme.subtleShadow,
          ),
        ),
      ),
    );
  }
}
