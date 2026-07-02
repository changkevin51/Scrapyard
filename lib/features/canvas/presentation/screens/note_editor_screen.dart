import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/canvas_providers.dart';
import '../widgets/handwriting_canvas.dart';
import '../widgets/canvas_toolbar.dart';
import '../widgets/canvas_smart_widgets.dart';
import '../widgets/canvas_text_sticker.dart';
import '../widgets/document_tab_bar.dart';
import '../widgets/sticker_library.dart';
import '../../domain/models/stroke.dart';
import '../../data/canvas_ocr_service.dart';
import '../../../ai_engine/domain/models/contextual_query.dart';
import '../../../ai_engine/presentation/providers/contextual_engine_provider.dart';
import '../../../ai_engine/presentation/widgets/contextual_popup.dart';
import '../../../memory/presentation/widgets/usefulness_rater.dart';

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
  OverlayEntry? _popupEntry;
  OverlayEntry? _raterEntry;
  Offset? _lastPopupPosition;
  Offset? _lassoStart;
  Rect? _lassoRect;
  Rect? _selectedStrokeBounds;

  @override
  void initState() {
    super.initState();
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
    _ocrService.dispose();
    _scrollController.dispose();
    _popupEntry?.remove();
    _raterEntry?.remove();
    super.dispose();
  }

  void _onCanvasTapDown(TapDownDetails details) {
    if (ref.read(activeCanvasToolProvider) == CanvasTool.lasso) {
      return;
    }

    if (ref.read(activeCanvasToolProvider) == CanvasTool.text) {
      final newText = CanvasTextItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        position: details.localPosition,
      );
      ref.read(canvasTextNodesProvider.notifier).update((s) => [...s, newText]);
      // Return here — HandwritingCanvas _onPointerUp will skip stroke
      // creation for short taps (< 10px movement), so both coexist cleanly.
      return;
    }

    if (ref.read(activeCanvasToolProvider) != CanvasTool.pen) return;

    final results = ref.read(ocrResultsProvider);
    if (results.isEmpty) return;

    CanvasOcrResult? nearest;
    double minDistance = double.maxFinite;

    for (var result in results) {
      final center = result.boundingBox.center;
      final touch  = details.localPosition;
      final dist   = (center - touch).distance;
      if (dist < minDistance && dist < 50.0) {
        minDistance = dist;
        nearest = result;
      }
    }

    if (nearest != null) {
      _showPopup(nearest.text, details.globalPosition);
    } else {
      _removePopup();
    }
  }

  void _startLasso(DragStartDetails details) {
    if (ref.read(activeCanvasToolProvider) != CanvasTool.lasso) return;
    setState(() {
      _lassoStart = details.localPosition;
      _lassoRect = Rect.fromPoints(details.localPosition, details.localPosition);
    });
  }

  void _updateLasso(DragUpdateDetails details) {
    if (_lassoStart == null || ref.read(activeCanvasToolProvider) != CanvasTool.lasso) return;
    setState(() {
      _lassoRect = Rect.fromPoints(_lassoStart!, details.localPosition);
    });
  }

  void _endLasso(DragEndDetails details) {
    if (_lassoStart == null || _lassoRect == null) return;

    final selection = _normalizedRect(_lassoRect!);
    final strokes = ref.read(strokesProvider);
    final selectedStrokes = strokes
        .where((stroke) => !stroke.isHidden && _strokeIntersectsSelection(stroke, selection))
        .toList();

    setState(() {
      _selectedStrokeBounds = selectedStrokes.isEmpty
        ? null
        : _unionRects(selectedStrokes.map((stroke) => _strokeBounds(stroke).inflate(4)).toList());
    });

    final ocrResults = ref.read(ocrResultsProvider);
    final selected = ocrResults.where((result) {
      return selection.overlaps(result.boundingBox);
    }).toList();

    if (selected.isNotEmpty) {
      final selectedText = selected.map((r) => r.text).join(' ');
      _showPopup(selectedText, selection.center);
    } else {
      _removePopup();
    }

    setState(() {
      _lassoStart = null;
      _lassoRect = null;
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
    final bounds = _strokeBounds(stroke);
    if (bounds.overlaps(selection)) return true;

    for (final point in stroke.points) {
      if (selection.contains(Offset(point.x, point.y))) return true;
    }

    return false;
  }

  Rect _normalizedRect(Rect rect) {
    return Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
  }

  void _showPopup(String selectedText, Offset position) {
    _lastPopupPosition = position;
    _popupEntry?.remove();

    final query = ContextualQuery(
      selectedText: selectedText,
      surroundingContext: selectedText,
      queryMode: QueryMode.explain,
    );
    ref.read(contextualEngineProvider.notifier).triggerQuery(query);

    _popupEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy + 30,
        left: position.dx,
        child: Material(
          color: Colors.transparent,
          child: ContextualPopup(onDismiss: _removePopup),
        ),
      ),
    );
    Overlay.of(context).insert(_popupEntry!);
  }

  void _removePopup() {
    final logId = ref.read(contextualEngineProvider).currentLogId;
    if (logId != null && _lastPopupPosition != null) {
      _showUsefulnessRater(logId, _lastPopupPosition!);
    }
    ref.read(contextualEngineProvider.notifier).clearState();
    _popupEntry?.remove();
    _popupEntry = null;
  }

  void _showUsefulnessRater(String logId, Offset position) {
    _raterEntry?.remove();
    _raterEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy + 30,
        left: position.dx,
        child: Material(
          color: Colors.transparent,
          child: UsefulnessRater(logId: logId),
        ),
      ),
    );
    Overlay.of(context).insert(_raterEntry!);
    Future.delayed(const Duration(seconds: 3), () {
      if (_raterEntry != null && mounted) {
        _raterEntry!.remove();
        _raterEntry = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(strokesProvider, (previous, next) {
      if (previous != null && next.length > previous.length) _triggerOcrRun();
    });

    final isPenMode       = ref.watch(isPenModeActiveProvider);
    final isLassoMode     = ref.watch(activeCanvasToolProvider) == CanvasTool.lasso;
    final toolbarPosition = ref.watch(toolbarPositionProvider);

    final canvasStack = Stack(
      children: [
        const HandwritingCanvas(),
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
    );

    final canvasSurface = Expanded(
      child: Stack(
        children: [
          GestureDetector(
            onTapDown: _onCanvasTapDown,
            onPanStart: _startLasso,
            onPanUpdate: _updateLasso,
            onPanEnd: _endLasso,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: (isPenMode || isLassoMode)
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                width: double.infinity,
                height: 5000,
                child: canvasStack,
              ),
            ),
          ),
          if (_lassoRect != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LassoPainter(_lassoRect!),
                ),
              ),
            ),
          if (_selectedStrokeBounds != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SelectedStrokeHighlightPainter(_selectedStrokeBounds!),
                ),
              ),
            ),
          // Smart action FAB — bottom right
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
          SafeArea(bottom: false, child: CanvasToolbar()),
          canvasSurface,
        ]);
        break;
      case ToolbarPosition.bottom:
        toolSurface = Column(children: [
          canvasSurface,
          SafeArea(top: false, child: CanvasToolbar()),
        ]);
        break;
      case ToolbarPosition.left:
        toolSurface = SafeArea(child: Row(children: [CanvasToolbar(), canvasSurface]));
        break;
      case ToolbarPosition.right:
        toolSurface = SafeArea(child: Row(children: [canvasSurface, CanvasToolbar()]));
        break;
    }

    return Scaffold(
      backgroundColor: KotoTheme.background,
      body: Column(
        children: [
          SafeArea(bottom: false, child: const DocumentTabBar()),
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
        final segmentEnd = math.min(distance + dashLength, totalLength);
        canvas.drawLine(
          start + direction * distance,
          start + direction * segmentEnd,
          paint,
        );
        distance += dashLength + gapLength;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _SelectedStrokeHighlightPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}
