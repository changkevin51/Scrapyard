import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/smelt_popup.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_chat/presentation/widgets/ai_chat_panel.dart';
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


class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final ScrollController _scrollController = ScrollController();
  final CanvasOcrService _ocrService = CanvasOcrService();
  final GlobalKey<SmeltPopupState> _smeltPopupKey = GlobalKey<SmeltPopupState>();

  Timer? _ocrDebounce;
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
  bool _isSmelting = false;
  bool _manualHintVisible = false;
  Offset? _manualSelectMenuAnchor;
  Timer? _manualHintTimer;
  int? _selectionPointerId;
  Offset? _selectionDownPos;
  bool _selectionDragStarted = false;
  bool _selectionPointerIsStylus = false;
  /// True while the chat panel has requested a canvas region for attachment.
  bool _chatCaptureMode = false;

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

    final cacheKey = _smeltCacheKeyFor(cluster.strokeIds);
    final hasCached = ref.read(smeltProvider.notifier).hasCached(cacheKey);

    setState(() {
      _selectionRect = cluster.bounds;
      _selectedStrokeIds = Set<String>.from(cluster.strokeIds);
      _activeClusterId = cluster.id;
      _selectionFromDetection = true;
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });

    if (hasCached) {
      // Reopen the saved popup for this expression — no API call / no action menu.
      ref.read(smeltProvider.notifier).restoreCached(cacheKey);
      _showSmeltPopup(cluster.bounds);
      return;
    }

    // Keep action chips hidden while a response popup is already open.
    if (_smeltPopupEntry != null) return;

    setState(() => _showSelectionMenu = true);
  }

  String _smeltCacheKeyFor(Iterable<String> strokeIds) {
    return SmeltNotifier.cacheKeyFor(
      noteId: ref.read(activeNoteIdProvider),
      strokeIds: strokeIds,
    );
  }

  bool _selectionHasCachedSmelt() {
    if (_selectedStrokeIds.isEmpty) return false;
    return ref
        .read(smeltProvider.notifier)
        .hasCached(_smeltCacheKeyFor(_selectedStrokeIds));
  }

  /// Action chips stay hidden while a response popup is open or already cached.
  bool get _smeltActionMenuAllowed =>
      _smeltPopupEntry == null && !_selectionHasCachedSmelt();

  /// Show the smelt action menu, or reopen a cached response instead.
  void _revealSmeltSelectionOrCachedPopup() {
    if (_selectionRect == null || _selectedStrokeIds.isEmpty) return;
    if (_smeltPopupEntry != null) return;

    final key = _smeltCacheKeyFor(_selectedStrokeIds);
    final notifier = ref.read(smeltProvider.notifier);
    if (notifier.hasCached(key)) {
      notifier.restoreCached(key);
      setState(() => _showSelectionMenu = false);
      _showSmeltPopup(_selectionRect!);
      return;
    }

    setState(() => _showSelectionMenu = true);
  }

  void _onSelectionPointerDown(PointerDownEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (!_isSelectionTool(ref.read(activeCanvasToolProvider))) return;

    final isStylus = _isStylusPointer(event.kind);
    final isTouchSmelt = event.kind == PointerDeviceKind.touch &&
        ref.read(activeCanvasToolProvider) == CanvasTool.smelt;
    if (!isStylus && !isTouchSmelt) return;

    _selectionPointerId = event.pointer;
    _selectionDownPos = event.localPosition;
    _selectionDragStarted = false;
    _selectionPointerIsStylus = isStylus;
  }

  void _onSelectionPointerMove(PointerMoveEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (_selectionPointerId != event.pointer) return;
    if (_selectionDownPos == null) return;

    if (!_selectionDragStarted) {
      if ((event.localPosition - _selectionDownPos!).distance <
          _selectionDragSlop) {
        return;
      }
      _selectionDragStarted = true;
      if (_selectionPointerIsStylus) {
        _startLassoAt(_selectionDownPos!);
      }
    }

    if (_lassoStart != null) {
      _updateLassoTo(event.localPosition);
    }
  }

  void _onSelectionPointerUp(PointerUpEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (_selectionPointerId != event.pointer) return;

    if (_selectionPointerIsStylus) {
      if (_selectionDragStarted && _lassoStart != null) {
        _finishLassoGesture();
      } else if (!_selectionDragStarted &&
          ref.read(activeCanvasToolProvider) == CanvasTool.smelt) {
        _handleSmeltTapAt(event.localPosition);
      }
    } else if (!_selectionDragStarted &&
        ref.read(activeCanvasToolProvider) == CanvasTool.smelt) {
      _handleSmeltTapAt(event.localPosition);
    }

    _resetSelectionPointer();
  }

  void _onSelectionPointerCancel(PointerCancelEvent event) {
    if (_selectionPointerId != event.pointer) return;
    _resetSelectionPointer();
    if (_lassoStart != null) {
      setState(() {
        _lassoStart = null;
        _lassoPreviewRect = null;
      });
    }
  }

  void _resetSelectionPointer() {
    _selectionPointerId = null;
    _selectionDownPos = null;
    _selectionDragStarted = false;
    _selectionPointerIsStylus = false;
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
      _lassoStart = null;
      _lassoPreviewRect = null;
    });
    _hidePasteMenu();

    // Chat capture mode: auto-attach without showing the selection menu.
    if (_chatCaptureMode) {
      _attachSelectionToChat();
      return;
    }

    _refreshSelectionBounds(showMenu: false);
    if (ref.read(activeCanvasToolProvider) == CanvasTool.smelt) {
      _revealSmeltSelectionOrCachedPopup();
    } else {
      setState(() => _showSelectionMenu = true);
    }
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
        !_isSmelting &&
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
      _isSmelting = false;
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

  void _smeltSelection({bool forceRefresh = false}) async {
    if (_selectionRect == null || _selectedStrokeIds.isEmpty) return;
    _hideSelectionMenu();

    final rect = _selectionRect!;
    final cacheKey = _smeltCacheKeyFor(_selectedStrokeIds);
    final notifier = ref.read(smeltProvider.notifier);

    // Reuse a session-cached response unless the user asked to retry.
    if (!forceRefresh && notifier.hasCached(cacheKey)) {
      notifier.restoreCached(cacheKey);
      _showSmeltPopup(rect);
      return;
    }

    setState(() => _isSmelting = true);
    notifier.startLoading(cacheKey: cacheKey);

    // Show the popup immediately so loading / retry happens in-place.
    if (_smeltPopupEntry == null) {
      _showSmeltPopup(rect);
    }

    // Capture the canvas region as an image
    Uint8List? imageBytes;
    try {
      imageBytes = await _captureCanvasRegion(rect);
    } catch (_) {
      // If capture fails, fall back to null (text-only mode)
    }

    // Send to AI (stores into session cache on success)
    await notifier.smelt(imageBytes: imageBytes, cacheKey: cacheKey);

    if (mounted) {
      setState(() => _isSmelting = false);
      // Don't reopen if the user dismissed mid-request — cache still saves.
      _smeltPopupEntry?.markNeedsBuild();
    }
  }

  void _retrySmelt() {
    if (_selectionRect != null && _selectedStrokeIds.isNotEmpty) {
      _smeltSelection(forceRefresh: true);
      return;
    }
    // Selection cleared — reuse the last captured image if we still have it.
    ref.read(smeltProvider.notifier).retry();
  }

  /// Capture the current selection and stage it as a chat attachment.
  Future<void> _attachSelectionToChat() async {
    final rect = _selectionRect;
    if (rect == null || _selectedStrokeIds.isEmpty) return;
    _hideSelectionMenu();

    Uint8List? bytes;
    try {
      bytes = await _captureCanvasRegion(rect, maxWidth: 1000);
    } catch (_) {}

    if (!mounted) return;

    if (bytes != null) {
      ref.read(pendingChatAttachmentProvider.notifier).state = bytes;
      ref.read(chatPanelOpenProvider.notifier).state = true;
    }

    ref.read(chatCaptureRequestProvider.notifier).state = false;
    setState(() {
      _chatCaptureMode = false;
      _lassoStart = null;
      _lassoPreviewRect = null;
      _selectionRect = null;
      _selectedStrokeIds = {};
      _showSelectionMenu = false;
      _selectionFromDetection = false;
      _activeClusterId = null;
      _manualHintVisible = false;
    });
  }

  Future<Uint8List?> _captureCanvasRegion(
    Rect region, {
    int? maxWidth,
  }) async {
    final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;

    const pixelRatio = 2.0;
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

    if (clampedCropRect.width <= 0 || clampedCropRect.height <= 0) {
      image.dispose();
      return null;
    }

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

    // Optionally downscale for chat attachments (keeps DB/base64 size sane).
    final needsDownscale = maxWidth != null &&
        clampedCropRect.width > maxWidth;
    final needsCompress = bytes.length > 1024 * 1024;

    if (needsDownscale || needsCompress) {
      final targetW = needsDownscale
          ? maxWidth
          : (clampedCropRect.width * 0.5).round();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW,
      );
      final frame = await codec.getNextFrame();
      final compressed = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
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
    if (_showSelectionMenu) {
      _showSelectionMenu = false;
    }

    // Convert to global coordinates for the popup positioning
    final globalRect = _convertToGlobalRect(selectionRect);
    ScrapFeedback.action();

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
            key: _smeltPopupKey,
            selectionRect: globalRect,
            onDismiss: _removeSmeltPopup,
            onRetry: _retrySmelt,
            screenSize: MediaQuery.of(context).size,
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_smeltPopupEntry!);
    // Rebuild canvas overlays so the action menu hides while popup is open.
    if (mounted) setState(() {});
  }

  void _dismissSmeltPopup() {
    final state = _smeltPopupKey.currentState;
    if (state != null) {
      state.dismiss();
      return;
    }
    _removeSmeltPopup();
  }

  void _removeSmeltPopup() {
    _smeltPopupEntry?.remove();
    _smeltPopupEntry = null;
    ref.read(smeltProvider.notifier).clearState();
    // Rebuild so action-menu gating re-evaluates after popup closes.
    if (mounted) setState(() {});
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
      // Cancel an in-progress chat capture if the user picks another tool.
      if (_chatCaptureMode && previous != next && next != CanvasTool.lasso) {
        ref.read(chatCaptureRequestProvider.notifier).state = false;
        setState(() => _chatCaptureMode = false);
      }
    });

    ref.listen<bool>(chatCaptureRequestProvider, (previous, next) {
      if (next == true && previous != true) {
        _manualHintTimer?.cancel();
        ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.lasso;
        ref.read(isPenModeActiveProvider.notifier).state = true;
        setState(() {
          _chatCaptureMode = true;
          _lassoStart = null;
          _lassoPreviewRect = null;
          _selectionRect = null;
          _selectedStrokeIds = {};
          _showSelectionMenu = false;
          _isResizingSelection = false;
          _selectionFromDetection = false;
          _activeClusterId = null;
          _manualSelectMenuAnchor = null;
          _manualHintVisible = true;
        });
        _manualHintTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _manualHintVisible = false);
        });
      } else if (next == false && _chatCaptureMode) {
        setState(() {
          _chatCaptureMode = false;
          _manualHintVisible = false;
        });
      }
    });

    // If the user reopens chat without finishing a capture, cancel capture mode.
    ref.listen<bool>(chatPanelOpenProvider, (previous, next) {
      if (next == true &&
          _chatCaptureMode &&
          ref.read(pendingChatAttachmentProvider) == null) {
        ref.read(chatCaptureRequestProvider.notifier).state = false;
      }
    });

    ref.listen<bool>(stylusOnlyModeProvider, (previous, next) {
      if (next && mounted) {
        _manualHintTimer?.cancel();
        _resetSelectionPointer();
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

    final strokes = ref.watch(strokesProvider);
    final canvasStack = RepaintBoundary(
      key: _canvasRepaintKey,
      child: Stack(
        children: [
          HandwritingCanvas(
            scrollController: _scrollController,
            zoomLevel: canvasZoom,
            onZoomChanged: (v) => ref.read(canvasZoomProvider.notifier).state = v,
          ),
          // Soft paper grain — cached 64×64 tile, one drawRect, IgnorePointer
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: PaperGrain(opacity: 0.022),
              ),
            ),
          ),
          // Empty-sheet affordance
          if (strokes.isEmpty)
            const Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: _FreshScrapHint(),
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
              _SelectionBoxHighlight(
                key: ValueKey(_activeClusterId ?? 'selection'),
                rect: _selectionRect!,
                fromDetection: _selectionFromDetection,
                isSmelting: _isSmelting,
              ),
              if (!_isResizingSelection && !_isSmelting)
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
              if (_showSelectionMenu && isSmeltMode && _smeltActionMenuAllowed)
                _SmeltActionMenu(
                  rect: _selectionRect!,
                  showManualSelect: _selectionFromDetection,
                  onSmelt: _smeltSelection,
                  onAddToChat: _attachSelectionToChat,
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
    if (_manualHintVisible && (isSmeltMode || _chatCaptureMode) && !stylusOnly) {
      contentOverlays.add(
        Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Transform.rotate(
                angle: -0.6 * math.pi / 180,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: ScrapTheme.cardSurface,
                    borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                    border: Border.all(color: ScrapTheme.dividers),
                    boxShadow: ScrapTheme.subtleShadow,
                  ),
                  child: Text(
                    _chatCaptureMode
                        ? 'Drag to select for chat'
                        : 'Drag to select',
                    style: ScrapTextStyles.caption.copyWith(
                      color: ScrapTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
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

    // Plain Stack — callers wrap in Expanded as needed (never nest Expanded).
    final canvasSurface = Stack(
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
            // Desk tone when zoomed out so the sheet sits on a surface
            color: canvasZoom <= 1.0
                ? ScrapTheme.codeSurface
                : ScrapTheme.background,
            child: SizedBox(
              width: double.infinity,
              height: 5000 * canvasZoom,
              child: Transform.scale(
                scale: canvasZoom,
                alignment: canvasZoom <= 1.0
                    ? const Alignment(0, -1)
                    : Alignment.topLeft,
                child: DecoratedBox(
                  decoration: canvasZoom <= 1.0
                      ? const BoxDecoration(boxShadow: ScrapTheme.subtleShadow)
                      : const BoxDecoration(),
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
        ),
        // AI chat FAB — bottom right, always on screen
        const Positioned(
          right: 16,
          bottom: 16,
          child: CanvasSmartBar(),
        ),
      ],
    );

    Widget toolSurface;
    switch (toolbarPosition) {
      case ToolbarPosition.top:
        toolSurface = Column(children: [
          const CanvasToolbar(),
          Expanded(child: canvasSurface),
        ]);
        break;
      case ToolbarPosition.bottom:
        toolSurface = Column(children: [
          Expanded(child: canvasSurface),
          const SafeArea(top: false, child: CanvasToolbar()),
        ]);
        break;
      case ToolbarPosition.left:
        toolSurface = SafeArea(
          child: Row(children: [
            const CanvasToolbar(),
            Expanded(child: canvasSurface),
          ]),
        );
        break;
      case ToolbarPosition.right:
        toolSurface = SafeArea(
          child: Row(children: [
            Expanded(child: canvasSurface),
            const CanvasToolbar(),
          ]),
        );
        break;
    }

    return Scaffold(
      backgroundColor: ScrapTheme.background,
      body: Stack(
        children: [
          Column(
            children: [
              const SafeArea(bottom: false, child: DocumentTabBar()),
              Expanded(child: toolSurface),
            ],
          ),
          const AiChatPanel(),
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
      ..color = ScrapTheme.accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) => oldDelegate.rect != rect;
}

class _SelectionBoxHighlight extends StatefulWidget {
  final Rect rect;
  final bool fromDetection;
  final bool isSmelting;

  const _SelectionBoxHighlight({
    super.key,
    required this.rect,
    required this.fromDetection,
    required this.isSmelting,
  });

  @override
  State<_SelectionBoxHighlight> createState() => _SelectionBoxHighlightState();
}

class _SelectionBoxHighlightState extends State<_SelectionBoxHighlight>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.isSmelting) _ensureController();
  }

  @override
  void didUpdateWidget(covariant _SelectionBoxHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSmelting && !oldWidget.isSmelting) {
      _ensureController();
    } else if (!widget.isSmelting && oldWidget.isSmelting) {
      _disposeController();
    }
  }

  void _ensureController() {
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  CustomPainter _painter({
    required bool smelting,
    required double pulseOpacity,
    required double dashOffset,
    required double scanProgress,
  }) {
    if (widget.fromDetection) {
      return _DetectedBoxPainter(
        widget.rect,
        smelting: smelting,
        pulseOpacity: pulseOpacity,
        dashOffset: dashOffset,
        scanProgress: scanProgress,
      );
    }
    return _SelectedStrokeHighlightPainter(
      widget.rect,
      smelting: smelting,
      pulseOpacity: pulseOpacity,
      dashOffset: dashOffset,
      scanProgress: scanProgress,
    );
  }

  Widget _buildPaint({
    required bool smelting,
    required double pulseOpacity,
    required double dashOffset,
    required double scanProgress,
  }) {
    return CustomPaint(
      painter: _painter(
        smelting: smelting,
        pulseOpacity: pulseOpacity,
        dashOffset: dashOffset,
        scanProgress: scanProgress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget box;
    if (widget.isSmelting && _controller != null) {
      box = AnimatedBuilder(
        animation: _controller!,
        builder: (context, _) {
          final t = _controller!.value;
          return _buildPaint(
            smelting: true,
            pulseOpacity: 0.55 + 0.25 * math.sin(t * 2 * math.pi),
            dashOffset: t,
            scanProgress: t,
          );
        },
      );
    } else {
      box = _buildPaint(
        smelting: false,
        pulseOpacity: 1.0,
        dashOffset: 0.0,
        scanProgress: -1.0,
      );
    }

    if (widget.fromDetection && !widget.isSmelting) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: box,
      );
    }

    return box;
  }
}

class _SelectedStrokeHighlightPainter extends CustomPainter {
  final Rect rect;
  final bool smelting;
  final double pulseOpacity;
  final double dashOffset;
  final double scanProgress;

  _SelectedStrokeHighlightPainter(
    this.rect, {
    this.smelting = false,
    this.pulseOpacity = 1.0,
    this.dashOffset = 0.0,
    this.scanProgress = -1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (smelting) {
      final fill = Paint()
        ..color = ScrapTheme.accent.withValues(alpha: pulseOpacity * 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fill);
      _SelectionBoxPaintHelpers.drawScanSweep(canvas, rect, scanProgress);
    }

    final borderColor = smelting
        ? ScrapTheme.accent.withValues(alpha: pulseOpacity * 0.85)
        : const Color(0xFF7AA7D8).withValues(alpha: 0.55);
    final border = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = smelting ? 2.0 : 1.4;

    if (smelting) {
      _SelectionBoxPaintHelpers.drawAnimatedDashedRect(
        canvas,
        rect,
        border,
        dashOffset,
      );
    } else {
      _SelectionBoxPaintHelpers.drawDashedRect(canvas, rect, border);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectedStrokeHighlightPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.smelting != smelting ||
      oldDelegate.pulseOpacity != pulseOpacity ||
      oldDelegate.dashOffset != dashOffset ||
      oldDelegate.scanProgress != scanProgress;
}

class _DetectedBoxPainter extends CustomPainter {
  final Rect rect;
  final bool smelting;
  final double pulseOpacity;
  final double dashOffset;
  final double scanProgress;

  _DetectedBoxPainter(
    this.rect, {
    this.smelting = false,
    this.pulseOpacity = 1.0,
    this.dashOffset = 0.0,
    this.scanProgress = -1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final fillAlpha = smelting ? pulseOpacity * 0.12 : 0.06;
    final fill = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: fillAlpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, fill);

    if (smelting) {
      _SelectionBoxPaintHelpers.drawScanSweep(canvas, rect, scanProgress);
    }

    final border = Paint()
      ..color = ScrapTheme.accent
          .withValues(alpha: smelting ? pulseOpacity * 0.85 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = smelting ? 2.0 : 1.4;

    if (smelting) {
      _SelectionBoxPaintHelpers.drawAnimatedDashedRRect(
        canvas,
        rrect,
        border,
        dashOffset,
      );
    } else {
      _SelectionBoxPaintHelpers.drawDashedRRect(canvas, rrect, border);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectedBoxPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.smelting != smelting ||
      oldDelegate.pulseOpacity != pulseOpacity ||
      oldDelegate.dashOffset != dashOffset ||
      oldDelegate.scanProgress != scanProgress;
}

class _SelectionBoxPaintHelpers {
  static void drawScanSweep(Canvas canvas, Rect rect, double scanProgress) {
    if (scanProgress < 0) return;

    final bandH = math.max(8.0, rect.height * 0.12);
    final y = (rect.height + bandH) * scanProgress - bandH;
    final sweepRect = Rect.fromLTWH(rect.left, rect.top + y, rect.width, bandH);
    final sweepPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ScrapTheme.accent.withValues(alpha: 0.0),
          ScrapTheme.accent.withValues(alpha: 0.18),
          ScrapTheme.accent.withValues(alpha: 0.0),
        ],
      ).createShader(sweepRect);
    canvas.drawRect(sweepRect.intersect(rect), sweepPaint);
  }

  static void drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;

    void drawDashedLine(Offset start, Offset end) {
      final totalLength = (end - start).distance;
      if (totalLength == 0) return;

      final direction = (end - start) / totalLength;
      double distance = 0;
      while (distance < totalLength) {
        final from = start + direction * distance;
        final to = start +
            direction * math.min(distance + dashLength, totalLength);
        canvas.drawLine(from, to, paint);
        distance += dashLength + gapLength;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  static void drawAnimatedDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double offset,
  ) {
    const dashLen = 8.0;
    const gapLen = 6.0;
    const totalDash = dashLen + gapLen;

    void drawSide(Offset start, Offset end) {
      final length = (end - start).distance;
      if (length == 0) return;
      final dir = (end - start) / length;
      final shift = offset * totalDash;
      double d = -shift % totalDash;
      while (d < length) {
        final segEnd = math.min(d + dashLen, length);
        if (segEnd > 0 && d < length) {
          canvas.drawLine(
            start + dir * math.max(d, 0),
            start + dir * segEnd,
            paint,
          );
        }
        d += totalDash;
      }
    }

    drawSide(rect.topLeft, rect.topRight);
    drawSide(rect.topRight, rect.bottomRight);
    drawSide(rect.bottomRight, rect.bottomLeft);
    drawSide(rect.bottomLeft, rect.topLeft);
  }

  static void drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 4.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLength;
      }
    }
  }

  static void drawAnimatedDashedRRect(
    Canvas canvas,
    RRect rrect,
    Paint paint,
    double offset,
  ) {
    const dashLen = 8.0;
    const gapLen = 6.0;
    const totalDash = dashLen + gapLen;
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      final shift = offset * totalDash;
      double distance = -shift % totalDash;
      while (distance < metric.length) {
        final next = math.min(distance + dashLen, metric.length);
        if (next > 0) {
          canvas.drawPath(metric.extractPath(math.max(distance, 0), next), paint);
        }
        distance = next + gapLen;
      }
    }
  }
}

class _CopiedSelection {
  final List<Stroke> strokes;
  final Rect bounds;

  const _CopiedSelection({required this.strokes, required this.bounds});
}

/// Shared paper-chit shell for selection / smelt / paste menus.
class _PaperChit extends StatelessWidget {
  final Widget child;

  const _PaperChit({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1.0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: Transform.rotate(
        angle: -0.6 * math.pi / 180,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: ScrapTheme.cardSurface,
              borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              border: Border.all(color: ScrapTheme.dividers),
              boxShadow: ScrapTheme.subtleShadow,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FreshScrapHint extends StatefulWidget {
  const _FreshScrapHint();

  @override
  State<_FreshScrapHint> createState() => _FreshScrapHintState();
}

class _FreshScrapHintState extends State<_FreshScrapHint> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: ScrapMotion.panel,
        curve: ScrapMotion.panelCurve,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScrapStampLabel(text: '⟨ fresh scrap ⟩'),
            const SizedBox(height: 10),
            Text(
              'scribble anything — Smelt figures it out',
              textAlign: TextAlign.center,
              style: ScrapTextStyles.stamp.copyWith(
                fontSize: 11,
                color: ScrapTheme.mutedText.withValues(alpha: 0.7),
                letterSpacing: 0.8,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      child: _PaperChit(
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
    );
  }
}

class _SmeltActionMenu extends StatelessWidget {
  final Rect rect;
  final bool showManualSelect;
  final VoidCallback onSmelt;
  final VoidCallback onAddToChat;
  final VoidCallback onManualSelect;

  const _SmeltActionMenu({
    required this.rect,
    required this.showManualSelect,
    required this.onSmelt,
    required this.onAddToChat,
    required this.onManualSelect,
  });

  @override
  Widget build(BuildContext context) {
    final top = math.max(rect.top - 64, 12.0);
    final left = math.max(rect.left, 12.0);

    return Positioned(
      top: top,
      left: left,
      child: _PaperChit(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmeltPillButton(onTap: onSmelt),
            const SizedBox(width: 8),
            _AddToChatButton(onTap: onAddToChat),
            if (showManualSelect) ...[
              const SizedBox(width: 8),
              _ManualSelectButton(onTap: onManualSelect),
            ],
          ],
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
    return _PaperChit(
      child: _ManualSelectButton(onTap: onSelect),
    );
  }
}

class _MenuPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _MenuPressable({required this.child, required this.onTap});

  @override
  State<_MenuPressable> createState() => _MenuPressableState();
}

class _MenuPressableState extends State<_MenuPressable> {
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
        scale: _pressed ? 0.93 : 1.0,
        duration: ScrapMotion.press,
        curve: ScrapMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}

class _ManualSelectButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ManualSelectButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MenuPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
          border: Border.all(color: ScrapTheme.dividers),
        ),
        child: Text(
          'Select manually',
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.secondaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AddToChatButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddToChatButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MenuPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
          border: Border.all(color: ScrapTheme.dividers),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 14,
              color: ScrapTheme.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              'Add to chat',
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmeltPillButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SmeltPillButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _MenuPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ScrapTheme.accent, Color(0xFF8A6A55)],
          ),
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'Smelt',
              style: ScrapTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
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
    return _MenuPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFF7E6E6) : const Color(0xFFF5F1EC),
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        ),
        child: Text(
          label,
          style: ScrapTextStyles.caption.copyWith(
            color: danger ? const Color(0xFFB84444) : ScrapTheme.primaryText,
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
    return _PaperChit(
      child: _MenuPressable(
        onTap: onPaste,
        child: Text(
          'Paste',
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.accent,
            fontWeight: FontWeight.w700,
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
            border: Border.all(color: ScrapTheme.accent, width: 1.5),
            boxShadow: ScrapTheme.subtleShadow,
          ),
        ),
      ),
    );
  }
}
