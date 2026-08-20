import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/layout/scrap_layout.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../../../../core/widgets/paper_surfaces.dart' hide PaperChit;
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../ai_engine/smelt_timing.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/smelt_popup.dart';
import '../../../ai_engine/domain/models/smelt_response.dart';
import '../../../ai_engine/presentation/widgets/smelt_action_menu.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_chat/presentation/widgets/model_picker_sheet.dart';
import '../../../ai_chat/presentation/widgets/ai_chat_panel.dart';
import '../../../onboarding/domain/smelt_guide_step.dart';
import '../../../onboarding/presentation/providers/smelt_guide_provider.dart';
import '../providers/canvas_providers.dart';
import '../providers/canvas_viewport_provider.dart';
import '../providers/ink_calculator_provider.dart';
import '../providers/smelt_detection_provider.dart';
import '../widgets/handwriting_canvas.dart';
import '../widgets/ink_calculator_answer.dart';
import '../widgets/ink_calculator_popup.dart';
import '../widgets/infinite_canvas_surface.dart';
import '../widgets/canvas_toolbar.dart';
import '../widgets/canvas_smart_widgets.dart';
import '../widgets/canvas_text_sticker.dart';
import '../widgets/document_tab_bar.dart';
import '../widgets/pending_scrap_flow.dart';
import '../widgets/taped_slip.dart';
import '../../domain/models/stroke.dart';
import '../../data/canvas_ocr_service.dart';


class NoteEditorScreen extends ConsumerStatefulWidget {
  /// When false, the AI chat FAB/panel are omitted (hosted by a parent such as
  /// [PdfViewerScreen] so chat can open without the scrap split).
  final bool showChatChrome;

  /// When false, this editor is a child of another route (PDF split) and must
  /// not register [PopScope] — that would block the parent's back button.
  final bool ownsRoute;

  const NoteEditorScreen({
    super.key,
    this.showChatChrome = true,
    this.ownsRoute = true,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final CanvasOcrService _ocrService = CanvasOcrService();
  final GlobalKey<SmeltPopupState> _smeltPopupKey = GlobalKey<SmeltPopupState>();

  Timer? _ocrDebounce;
  int _textRevealGen = 0;
  OverlayEntry? _smeltPopupEntry;
  OverlayEntry? _inkCalcPopupEntry;
  final GlobalKey _canvasRepaintKey = GlobalKey();
  Offset? _lassoStart;
  Rect? _lassoPreviewRect;
  Rect? _selectionRect;
  Set<String> _selectedStrokeIds = {};
  Set<String> _selectedTextIds = {};
  bool _showSelectionMenu = false;
  bool _isResizingSelection = false;
  _CopiedSelection? _clipboardSelection;
  Offset? _pasteMenuAnchor;
  bool _showPasteMenu = false;
  String? _activeClusterId;
  bool _selectionFromDetection = false;
  bool _isSmelting = false;
  bool _manualHintVisible = false;
  bool _smeltHintVisible = false;
  Offset? _manualSelectMenuAnchor;
  Timer? _manualHintTimer;
  Timer? _smeltHintTimer;
  int? _selectionPointerId;
  Offset? _selectionDownPos;
  bool _selectionDragStarted = false;
  bool _selectionPointerIsStylus = false;
  /// True while the chat panel has requested a canvas region for attachment.
  bool _chatCaptureMode = false;
  bool _isMovingSelection = false;
  Offset? _lastSelectionDragGlobal;
  Offset? _lastEdgeScrollTickPointer;
  Timer? _selectionEdgeScrollTimer;

  static const double _selectionDragSlop = 8.0;
  static const double _selectionEdgeScrollMargin = 48.0;
  static const double _selectionEdgeScrollMinSpeed = 6.0;

  bool _isStylusPointer(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  bool _isSelectionTool(CanvasTool tool) =>
      tool == CanvasTool.lasso || tool == CanvasTool.smelt;

  bool _tapedSlipOwnsPointer([int? pointer]) {
    final active = ref.read(tapedSlipActivePointerProvider);
    if (active == null) return false;
    return pointer == null || active == pointer;
  }

  bool _pointerHitsMovableSelection(Offset localPosition) {
    if (_selectionRect == null) return false;
    if (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty) return false;
    if (_isResizingSelection || _isSmelting) return false;
    return _selectionRect!.contains(_toWorld(localPosition));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Warm up background cluster detection without watching (no rebuilds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_refSafe) return;
      ref.read(detectedClustersProvider);
      ref.read(inkCalculatorProvider);
      ref.read(smeltGuideProvider.notifier).resume();
    });
  }

  bool get _refSafe => mounted && context.mounted;

  @override
  void deactivate() {
    if (context.mounted) {
      ref.read(smeltGuideProvider.notifier).pause();
    }
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (widget.ownsRoute) {
      ref.read(smeltGuideProvider.notifier).resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ocrDebounce?.cancel();
    _ocrDebounce = null;
    _manualHintTimer?.cancel();
    _smeltHintTimer?.cancel();
    _selectionEdgeScrollTimer?.cancel();
    _ocrService.dispose();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    _smeltPopupEntry?.remove();
    _inkCalcPopupEntry?.remove();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_refSafe) return;
    if (ref.read(activeTextNodeIdProvider) != null) {
      _revealActiveTextAboveKeyboard();
    }
  }

  /// Scroll (finite) or pan (infinite) so the active text box clears the keyboard.
  void _revealActiveTextAboveKeyboard() {
    final gen = ++_textRevealGen;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!_refSafe || gen != _textRevealGen) return;
      if (ref.read(activeTextNodeIdProvider) == null) return;

      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      if (keyboard <= 0) return;

      // Prefer the live sticker rect; fall back to world-position estimate.
      Rect? globalRect = ref.read(activeTextGlobalRectProvider);
      if (globalRect == null) {
        final id = ref.read(activeTextNodeIdProvider);
        CanvasTextItem? node;
        for (final n in ref.read(canvasTextNodesProvider)) {
          if (n.id == id) {
            node = n;
            break;
          }
        }
        if (node == null) return;
        final canvasBox = _canvasRepaintKey.currentContext?.findRenderObject()
            as RenderBox?;
        if (canvasBox == null || !canvasBox.hasSize) return;
        final local = ref.read(pageLayoutProvider).isInfinite
            ? _toScreen(node.position)
            : node.position;
        final topLeft = canvasBox.localToGlobal(local);
        final h = math.max(40.0, node.fontSize * 1.4 + 36);
        globalRect = Rect.fromLTWH(topLeft.dx, topLeft.dy, 120, h);
      }

      final screenH = MediaQuery.sizeOf(context).height;
      const margin = 32.0;
      final targetBottom = screenH - keyboard - margin;
      final overflow = globalRect.bottom - targetBottom;
      if (overflow <= 1) return;

      if (ref.read(pageLayoutProvider).isInfinite) {
        ref
            .read(canvasViewportProvider.notifier)
            .panByScreenDelta(Offset(0, -overflow));
        return;
      }

      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      // Temporarily allow programmatic scroll even in pen mode.
      final next =
          (position.pixels + overflow).clamp(0.0, position.maxScrollExtent);
      if ((next - position.pixels).abs() < 1) return;
      await _scrollController.animateTo(
        next,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _triggerOcrRun() {
    _ocrDebounce?.cancel();
    if (!_refSafe) return;
    _ocrDebounce = Timer(const Duration(milliseconds: 1500), () async {
      if (!_refSafe) return;
      final strokes = ref.read(strokesProvider);
      final infinite = ref.read(pageLayoutProvider).isInfinite;
      BoxConstraints constraints;
      if (infinite) {
        final vp = ref.read(canvasViewportProvider);
        final size = ref.read(canvasViewportProvider.notifier).viewportSize;
        if (size.isEmpty) {
          constraints =
              const BoxConstraints(maxWidth: 2000, maxHeight: 2000);
        } else {
          final visible = vp.visibleWorld(size);
          constraints = BoxConstraints(
            maxWidth: math.max(visible.width, 1),
            maxHeight: math.max(visible.height, 1),
          );
        }
      } else {
        constraints =
            const BoxConstraints(maxWidth: 1000, maxHeight: 5000);
      }
      final results =
          await _ocrService.recognizeStrokes(strokes, constraints);
      if (!_refSafe) return;
      ref.read(ocrResultsProvider.notifier).state = results;
    });
  }

  /// Screen/local → world (identity in finite sheet mode).
  Offset _toWorld(Offset local) {
    if (!ref.read(pageLayoutProvider).isInfinite) return local;
    return ref.read(canvasViewportProvider).toWorld(local);
  }

  Offset _toScreen(Offset world) {
    if (!ref.read(pageLayoutProvider).isInfinite) return world;
    return ref.read(canvasViewportProvider).toScreen(world);
  }

  bool _hitsSmeltBoundingBox(Offset world) {
    if (_hitTextItem(world) != null) return true;
    final noteId = ref.read(activeNoteIdProvider);
    return ref.read(manualClustersProvider.notifier).hitTest(
              world,
              noteId: noteId,
            ) !=
            null ||
        ref.read(detectedClustersProvider.notifier).hitTest(world) != null;
  }

  void _onCanvasTapDown(TapDownDetails details) {
    if (_tapedSlipOwnsPointer()) return;
    final worldPos = _toWorld(details.localPosition);
    // Stylus mode: a finger tap on a detected box opens the smelt menu on
    // pointer-up; skip tap-down side effects (e.g. placing a text sticker).
    if (ref.read(stylusOnlyModeProvider) &&
        details.kind == PointerDeviceKind.touch &&
        _hitsSmeltBoundingBox(worldPos)) {
      return;
    }
    if (_selectionRect != null && !_selectionRect!.contains(worldPos)) {
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

    // Dismiss active text from any tool when tapping empty canvas.
    final activeTextId = ref.read(activeTextNodeIdProvider);
    final consumeDismiss = ref.read(consumeTextCanvasTapProvider);
    if (consumeDismiss) {
      ref.read(consumeTextCanvasTapProvider.notifier).state = false;
      if (tool == CanvasTool.text) return;
    }

    if (tool == CanvasTool.text) {
      // Tapping an existing text node is handled by the sticker itself.
      if (_hitsTextNode(worldPos)) return;

      // Tap elsewhere while editing → deselect (empty nodes prune themselves).
      if (activeTextId != null) {
        ref.read(activeTextNodeIdProvider.notifier).state = null;
        return;
      }

      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final newText = CanvasTextItem(id: id, position: worldPos);
      ref.read(canvasTextNodesProvider.notifier).add(newText);
      ref.read(activeTextNodeIdProvider.notifier).state = id;
      return;
    }

    if (activeTextId != null && !_hitsTextNode(worldPos)) {
      ref.read(activeTextNodeIdProvider.notifier).state = null;
    }

    if (tool != CanvasTool.pen) return;
  }

  /// Approximate hit-test for text stickers (world coordinates).
  bool _hitsTextNode(Offset worldPos) => _hitTextItem(worldPos) != null;

  Rect _textItemBounds(CanvasTextItem node) {
    final text = node.text.isEmpty ? '…' : node.text;
    final lines = text.split('\n');
    final maxLineLen =
        lines.fold<int>(1, (m, l) => l.length > m ? l.length : m);
    final font = node.fontSize;
    final w = math.max(48.0, maxLineLen * font * 0.55);
    final h = (lines.length * font * 1.35).clamp(28.0, 240.0);
    const chrome = 24.0;
    return Rect.fromLTWH(
      node.position.dx - chrome,
      node.position.dy - chrome,
      w + chrome * 2,
      h + chrome + 32,
    );
  }

  CanvasTextItem? _hitTextItem(Offset worldPos) {
    final nodes = ref.read(canvasTextNodesProvider);
    CanvasTextItem? best;
    var bestArea = double.infinity;
    for (final node in nodes) {
      if (node.taped || node.text.trim().isEmpty) continue;
      final rect = _textItemBounds(node);
      if (!rect.contains(worldPos)) continue;
      final area = rect.width * rect.height;
      if (area < bestArea) {
        bestArea = area;
        best = node;
      }
    }
    return best;
  }

  String? _selectedTextPayload() {
    if (_selectedTextIds.isEmpty) return null;
    final nodes = ref.read(canvasTextNodesProvider);
    final parts = nodes
        .where((n) => _selectedTextIds.contains(n.id) && n.text.trim().isNotEmpty)
        .map((n) => n.text.trim())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  bool get _hasSmeltableSelection =>
      _selectionRect != null &&
      (_selectedStrokeIds.isNotEmpty || _selectedTextIds.isNotEmpty);

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
    if (_tapedSlipOwnsPointer()) return;
    if (_lassoStart != null || _lassoPreviewRect != null) return;
    if (_tapHitsManualSelectMenu(_toWorld(details.localPosition))) return;
    _handleSmeltTapAt(details.localPosition);
  }

  void _handleSmeltTapAt(Offset position) {
    if (_tapedSlipOwnsPointer()) return;
    final world = _toWorld(position);
    if (_tapHitsManualSelectMenu(world)) return;

    // Prefer typed text boxes so smelt works on canvas text stickers.
    final textHit = _hitTextItem(world);
    if (textHit != null) {
      _hidePasteMenu();
      final cacheKey = _smeltCacheKeyFor(const [], textIds: [textHit.id]);
      final hasCached = ref.read(smeltProvider.notifier).hasCached(cacheKey);
      final bounds = _textItemBounds(textHit).inflate(4);

      setState(() {
        _selectionRect = bounds;
        _selectedStrokeIds = {};
        _selectedTextIds = {textHit.id};
        _activeClusterId = null;
        _selectionFromDetection = true;
        _showSelectionMenu = false;
        _isResizingSelection = false;
        _manualHintVisible = false;
        _manualSelectMenuAnchor = null;
      });

      if (hasCached && !_guideHoldsSmeltMenu) {
        ref.read(smeltGuideProvider.notifier).onSmeltRequested();
        ref.read(smeltProvider.notifier).restoreCached(cacheKey);
        _showSmeltPopup(bounds);
        return;
      }

      if (_smeltPopupEntry != null) return;
      setState(() => _showSelectionMenu = true);
      return;
    }

    final noteId = ref.read(activeNoteIdProvider);
    // Prefer user-corrected boxes so a manually fixed selection stays tappable
    // after the Smelt popup is dismissed.
    final cluster = ref.read(manualClustersProvider.notifier).hitTest(
              world,
              noteId: noteId,
            ) ??
        ref.read(detectedClustersProvider.notifier).hitTest(world);

    if (cluster == null) {
      if (ref.read(stylusOnlyModeProvider)) return;

      _hidePasteMenu();
      setState(() {
        _selectionRect = null;
        _selectedStrokeIds = {};
        _selectedTextIds = {};
        _activeClusterId = null;
        _selectionFromDetection = false;
        _showSelectionMenu = false;
        _manualSelectMenuAnchor = world;
      });
      return;
    }

    _hidePasteMenu();

    final cacheKey = _smeltCacheKeyFor(cluster.strokeIds);
    final hasCached = ref.read(smeltProvider.notifier).hasCached(cacheKey);

    setState(() {
      _selectionRect = cluster.bounds;
      _selectedStrokeIds = Set<String>.from(cluster.strokeIds);
      _selectedTextIds = {};
      _activeClusterId = cluster.id;
      // Manual corrections render like detected boxes (same dashed style).
      _selectionFromDetection = true;
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });

    if (hasCached && !_guideHoldsSmeltMenu) {
      // Reopen the saved popup for this expression — no API call / no action menu.
      ref.read(smeltGuideProvider.notifier).onSmeltRequested();
      ref.read(smeltProvider.notifier).restoreCached(cacheKey);
      _showSmeltPopup(cluster.bounds);
      return;
    }

    // Keep action chips hidden while an active response popup is already open.
    if (_smeltPopupEntry != null) return;

    setState(() => _showSelectionMenu = true);
  }

  bool _handleInkCalcTapAt(Offset position) {
    if (ref.read(activeCanvasToolProvider) == CanvasTool.smelt) return false;
    final noteId = ref.read(activeNoteIdProvider);
    final world = _toWorld(position);
    for (final calc in ref.read(inkCalculatorProvider).resultsFor(noteId)) {
      if (calc.containsWorld(world, pad: 10)) {
        _showInkCalcPopup(calc);
        return true;
      }
    }
    return false;
  }

  void _showInkCalcPopup(InkCalculatorResult result) {
    _inkCalcPopupEntry?.remove();
    final globalRect = _convertToGlobalRect(result.hitBounds);
    ScrapFeedback.tap();
    setState(() {
      _selectionRect = result.hitBounds.inflate(6);
      _selectedStrokeIds = {
        ...result.expressionStrokeIds,
        ...result.equalsStrokeIds,
      };
      _selectedTextIds = {};
      _activeClusterId = null;
      _selectionFromDetection = true;
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });
    _inkCalcPopupEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        return InkCalculatorPopup(
          result: result,
          selectionRect: globalRect,
          screenSize: screenSize,
          onDismiss: _dismissInkCalcPopup,
          onRemoveAnswer: () {
            _dismissInkCalcPopup();
            ref.read(inkCalculatorProvider.notifier).removeAnswer(result: result);
          },
          onUseSmelt: () => _useSmeltInsteadOfCalc(result),
        );
      },
    );
    Overlay.of(context).insert(_inkCalcPopupEntry!);
  }

  void _dismissInkCalcPopup({bool clearSelection = true}) {
    _inkCalcPopupEntry?.remove();
    _inkCalcPopupEntry = null;
    if (!clearSelection || !mounted) return;
    setState(() {
      _selectionRect = null;
      _selectedStrokeIds = {};
      _selectedTextIds = {};
      _activeClusterId = null;
      _selectionFromDetection = false;
      _showSelectionMenu = false;
    });
  }

  void _useSmeltInsteadOfCalc(InkCalculatorResult result) {
    _dismissInkCalcPopup(clearSelection: false);
    ref.read(inkCalculatorProvider.notifier).removeAnswer(result: result);
    final bounds =
        result.expressionBounds.expandToInclude(result.equalsBounds).inflate(8);
    setState(() {
      _selectionRect = bounds;
      _selectedStrokeIds = {
        ...result.expressionStrokeIds,
        ...result.equalsStrokeIds,
      };
      _selectedTextIds = {};
      _activeClusterId = null;
      _selectionFromDetection = true;
      _showSelectionMenu = false;
      _isResizingSelection = false;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _smeltSelection();
    });
  }

  String _smeltCacheKeyFor(
    Iterable<String> strokeIds, {
    Iterable<String>? textIds,
  }) {
    return SmeltNotifier.cacheKeyFor(
      noteId: ref.read(activeNoteIdProvider),
      strokeIds: strokeIds,
      textIds: textIds ?? _selectedTextIds,
    );
  }

  bool _selectionHasCachedSmelt() {
    if (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty) return false;
    return ref.read(smeltProvider.notifier).hasCached(
          _smeltCacheKeyFor(_selectedStrokeIds, textIds: _selectedTextIds),
        );
  }

  /// Action chips stay hidden while an active response popup is open or already cached.
  /// During the guide's select step, chips wait until the user taps Next.
  bool get _smeltActionMenuAllowed {
    if (_smeltPopupEntry != null) return false;
    final guide = ref.read(smeltGuideProvider);
    if (guide.isActive && guide.step == SmeltGuideStep.selectExpression) {
      return false;
    }
    if (guide.isActive && guide.step == SmeltGuideStep.chooseSmelt) {
      return true;
    }
    return !_selectionHasCachedSmelt();
  }

  bool get _guideHoldsSmeltMenu {
    final guide = ref.read(smeltGuideProvider);
    return guide.isActive && guide.step == SmeltGuideStep.selectExpression;
  }

  /// Show the smelt action menu, or reopen a cached response instead.
  void _revealSmeltSelectionOrCachedPopup() {
    if (!_hasSmeltableSelection) return;
    if (_smeltPopupEntry != null) return;

    final key =
        _smeltCacheKeyFor(_selectedStrokeIds, textIds: _selectedTextIds);
    if (_guideHoldsSmeltMenu) {
      setState(() => _showSelectionMenu = true);
      return;
    }
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
    if (_tapedSlipOwnsPointer(event.pointer)) return;

    final isStylus = _isStylusPointer(event.kind);
    final isTouch = event.kind == PointerDeviceKind.touch;
    final isSelection = _isSelectionTool(ref.read(activeCanvasToolProvider));

    if (isStylus) {
      if (!isSelection) return;
      // Let the selection-box pan handler move the box.
      if (_pointerHitsMovableSelection(event.localPosition)) return;
    } else if (!isTouch) {
      return;
    }

    // A second finger (pinch / two-finger tap) should not open smelt.
    if (_selectionPointerId != null) {
      _selectionDragStarted = true;
      return;
    }

    _selectionPointerId = event.pointer;
    _selectionDownPos = event.localPosition;
    _selectionDragStarted = false;
    _selectionPointerIsStylus = isStylus;
  }

  void _onSelectionPointerMove(PointerMoveEvent event) {
    if (!ref.read(stylusOnlyModeProvider)) return;
    if (_tapedSlipOwnsPointer(event.pointer)) return;
    if (_selectionPointerId != event.pointer) return;
    if (_selectionDownPos == null) return;

    if (!_selectionDragStarted) {
      if ((event.localPosition - _selectionDownPos!).distance <
          _selectionDragSlop) {
        return;
      }
      _selectionDragStarted = true;
      if (_selectionPointerIsStylus &&
          _isSelectionTool(ref.read(activeCanvasToolProvider))) {
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
    if (_tapedSlipOwnsPointer(event.pointer)) {
      _resetSelectionPointer();
      return;
    }

    if (_selectionPointerIsStylus) {
      if (_selectionDragStarted && _lassoStart != null) {
        _finishLassoGesture();
      } else if (!_selectionDragStarted &&
          ref.read(activeCanvasToolProvider) == CanvasTool.smelt) {
        _handleSmeltTapAt(event.localPosition);
      }
    } else if (!_selectionDragStarted) {
      if (_handleInkCalcTapAt(event.localPosition)) {
        _resetSelectionPointer();
        return;
      }
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
    if (_tapedSlipOwnsPointer()) return;
    _startLassoAt(details.localPosition);
  }

  void _startLassoAt(Offset position) {
    if (!_isSelectionTool(ref.read(activeCanvasToolProvider))) return;
    if (_tapedSlipOwnsPointer()) return;
    final world = _toWorld(position);
    _hideSelectionMenu();
    setState(() {
      _lassoStart = world;
      _lassoPreviewRect = Rect.fromPoints(world, world);
      _selectionFromDetection = false;
      _activeClusterId = null;
      _manualHintVisible = false;
      _manualSelectMenuAnchor = null;
    });
  }

  void _updateLasso(DragUpdateDetails details) {
    if (ref.read(stylusOnlyModeProvider)) return;
    if (_tapedSlipOwnsPointer()) return;
    _updateLassoTo(details.localPosition);
  }

  void _updateLassoTo(Offset position) {
    if (_lassoStart == null || !_isSelectionTool(ref.read(activeCanvasToolProvider))) {
      return;
    }

    final world = _toWorld(position);
    final draggedRect = _normalizedRect(Rect.fromPoints(_lassoStart!, world));
    final strokes = ref.read(strokesProvider);
    final selected = strokes
        .where((stroke) => !stroke.isHidden && _strokeIntersectsSelection(stroke, draggedRect))
        .toList();
    final textNodes = ref.read(canvasTextNodesProvider);
    final selectedTexts = textNodes
        .where((n) =>
            !n.taped &&
            n.text.trim().isNotEmpty &&
            _textItemBounds(n).overlaps(draggedRect))
        .toList();

    final boundRects = <Rect>[
      ...selected.map((stroke) => _strokeBounds(stroke).inflate(4)),
      ...selectedTexts.map((n) => _textItemBounds(n).inflate(4)),
    ];

    setState(() {
      _lassoPreviewRect = draggedRect;
      _selectionRect = boundRects.isEmpty ? null : _unionRects(boundRects);
      _selectedStrokeIds = selected.map((stroke) => stroke.id).toSet();
      _selectedTextIds = selectedTexts.map((n) => n.id).toSet();
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

    if (_selectionRect == null ||
        (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty)) {
      setState(() {
        _lassoStart = null;
        _lassoPreviewRect = null;
        _selectionRect = null;
        _selectedStrokeIds = {};
        _selectedTextIds = {};
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
        _selectedTextIds.isEmpty &&
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
      _selectedTextIds = {};
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
      _selectedTextIds = {};
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
    if (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty) return;

    _hideSelectionMenu();
    _hidePasteMenu();

    if (_selectedStrokeIds.isNotEmpty) {
      final strokes = ref.read(strokesProvider);
      final movedStrokes = <Stroke>[];

      for (final stroke in strokes) {
        if (_selectedStrokeIds.contains(stroke.id)) {
          movedStrokes.add(_translateStroke(stroke, delta));
        }
      }

      ref.read(strokesProvider.notifier).updateStrokes(movedStrokes);
    }

    if (_selectedTextIds.isNotEmpty) {
      final nodes = ref.read(canvasTextNodesProvider);
      final moved = [
        for (final node in nodes)
          if (_selectedTextIds.contains(node.id))
            node.copyWith(position: node.position + delta),
      ];
      ref.read(canvasTextNodesProvider.notifier).updateMany(moved);
    }

    setState(() {
      _selectionRect = _selectionRect!.shift(delta);
    });
  }

  /// Convert canvas-local / world rect to global screen coordinates.
  Rect _convertToGlobalRect(Rect localRect) {
    final renderBox =
        _canvasRepaintKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return localRect;

    if (ref.read(pageLayoutProvider).isInfinite) {
      final tl = _toScreen(localRect.topLeft);
      final br = _toScreen(localRect.bottomRight);
      final topLeft = renderBox.localToGlobal(tl);
      final bottomRight = renderBox.localToGlobal(br);
      return Rect.fromPoints(topLeft, bottomRight);
    }

    final topLeft = renderBox.localToGlobal(localRect.topLeft);
    final bottomRight = renderBox.localToGlobal(localRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  Rect? _scrollViewportGlobalRect() {
    if (ref.read(pageLayoutProvider).isInfinite) {
      final renderBox =
          _canvasRepaintKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return null;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      return topLeft & renderBox.size;
    }
    if (!_scrollController.hasClients) return null;
    final scrollBox = _scrollController.position.context.storageContext
        .findRenderObject() as RenderBox?;
    if (scrollBox == null || !scrollBox.hasSize) return null;
    final topLeft = scrollBox.localToGlobal(Offset.zero);
    return topLeft &
        Size(scrollBox.size.width, _scrollController.position.viewportDimension);
  }

  Offset _globalDeltaToCanvas(Offset globalDelta) {
    if (ref.read(pageLayoutProvider).isInfinite) {
      final scale = ref.read(canvasViewportProvider).scale;
      // Approximate: global ≈ screen for our stack; convert to world.
      return Offset(globalDelta.dx / scale, globalDelta.dy / scale);
    }
    final renderBox =
        _canvasRepaintKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return globalDelta;
    final origin = renderBox.globalToLocal(Offset.zero);
    final tip = renderBox.globalToLocal(globalDelta);
    return tip - origin;
  }

  void _startSelectionEdgeScrollTimer(double canvasZoom) {
    _selectionEdgeScrollTimer?.cancel();
    _selectionEdgeScrollTimer =
        Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_isMovingSelection || !mounted) return;
      final pointer = _lastSelectionDragGlobal;
      if (pointer == null) return;
      _tickSelectionEdgeScroll(pointer, canvasZoom);
    });
  }

  void _stopSelectionEdgeScrollTimer() {
    _selectionEdgeScrollTimer?.cancel();
    _selectionEdgeScrollTimer = null;
    _lastEdgeScrollTickPointer = null;
  }

  void _tickSelectionEdgeScroll(Offset globalPointer, double canvasZoom) {
    if (_selectionRect == null) return;
    final infinite = ref.read(pageLayoutProvider).isInfinite;
    if (!infinite && !_scrollController.hasClients) return;

    // Active drags are handled in [_handleSelectionDrag]; only auto-scroll
    // here when the pointer has stopped moving but is still held at the edge.
    if (_lastEdgeScrollTickPointer != globalPointer) {
      _lastEdgeScrollTickPointer = globalPointer;
      return;
    }

    final viewport = _scrollViewportGlobalRect();
    if (viewport == null) return;

    final globalRect = _convertToGlobalRect(_selectionRect!);
    final scrollDelta = _edgeScrollDeltaForDrag(
      globalPointer: globalPointer,
      globalSelectionRect: globalRect,
      viewport: viewport,
      canvasDelta: Offset.zero,
      canvasZoom: canvasZoom,
    );
    if (scrollDelta == 0) return;

    if (infinite) {
      // Pan the world viewport; keep selection under the pointer.
      ref
          .read(canvasViewportProvider.notifier)
          .panByScreenDelta(Offset(0, -scrollDelta));
      _moveSelection(Offset(0, scrollDelta / canvasZoom));
      return;
    }

    final scroll = _scrollController;
    final newOffset =
        (scroll.offset + scrollDelta).clamp(0.0, scroll.position.maxScrollExtent);
    final actualScroll = newOffset - scroll.offset;
    if (actualScroll == 0) return;

    scroll.jumpTo(newOffset);
    _moveSelection(Offset(0, actualScroll / canvasZoom));
  }

  double _edgeScrollDeltaForDrag({
    required Offset globalPointer,
    required Rect globalSelectionRect,
    required Rect viewport,
    required Offset canvasDelta,
    required double canvasZoom,
  }) {
    const margin = _selectionEdgeScrollMargin;
    final atBottom = globalSelectionRect.bottom >= viewport.bottom - margin ||
        globalPointer.dy >= viewport.bottom - margin;
    final atTop = globalSelectionRect.top <= viewport.top + margin ||
        globalPointer.dy <= viewport.top + margin;

    if (atBottom && canvasDelta.dy >= 0) {
      return canvasDelta.dy > 0
          ? canvasDelta.dy * canvasZoom
          : _selectionEdgeScrollMinSpeed;
    }
    if (atTop && canvasDelta.dy <= 0) {
      return canvasDelta.dy < 0
          ? canvasDelta.dy * canvasZoom
          : -_selectionEdgeScrollMinSpeed;
    }
    return 0;
  }

  void _handleSelectionDrag(
    Offset canvasDelta,
    Offset globalPointer,
    double canvasZoom,
  ) {
    _lastSelectionDragGlobal = globalPointer;
    final infinite = ref.read(pageLayoutProvider).isInfinite;
    if (!infinite && !_scrollController.hasClients) {
      _moveSelection(canvasDelta);
      return;
    }

    final viewport = _scrollViewportGlobalRect();
    if (viewport == null) {
      _moveSelection(canvasDelta);
      return;
    }

    final predictedGlobalRect =
        _convertToGlobalRect(_selectionRect!.shift(canvasDelta));
    final scrollDelta = _edgeScrollDeltaForDrag(
      globalPointer: globalPointer,
      globalSelectionRect: predictedGlobalRect,
      viewport: viewport,
      canvasDelta: canvasDelta,
      canvasZoom: canvasZoom,
    );

    var totalCanvasDelta = canvasDelta;
    if (scrollDelta != 0) {
      if (infinite) {
        ref
            .read(canvasViewportProvider.notifier)
            .panByScreenDelta(Offset(0, -scrollDelta));
        totalCanvasDelta = Offset(
          canvasDelta.dx,
          canvasDelta.dy + scrollDelta / canvasZoom,
        );
      } else {
        final scroll = _scrollController;
        final newOffset = (scroll.offset + scrollDelta)
            .clamp(0.0, scroll.position.maxScrollExtent);
        final actualScroll = newOffset - scroll.offset;
        if (actualScroll != 0) {
          scroll.jumpTo(newOffset);
          totalCanvasDelta = Offset(
            canvasDelta.dx,
            canvasDelta.dy + actualScroll / canvasZoom,
          );
        }
      }
    }

    _moveSelection(totalCanvasDelta);
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

  void _smeltSelection({
    bool forceRefresh = false,
    bool forceCodeExecution = false,
  }) async {
    if (!_hasSmeltableSelection) return;
    SmeltTiming.begin(extra: {
      'source': 'canvas',
      'forceRefresh': forceRefresh,
      'forceCodeExecution': forceCodeExecution,
    });
    ref.read(smeltGuideProvider.notifier).onSmeltRequested();
    _hideSelectionMenu();
    SmeltTiming.step('hid_selection_menu');

    // Persist user-corrected boxes for the session so tapping the expression
    // reopens the cached Smelt popup after dismiss.
    if (!_selectionFromDetection && _selectedStrokeIds.isNotEmpty) {
      ref.read(manualClustersProvider.notifier).remember(
            noteId: ref.read(activeNoteIdProvider),
            strokeIds: _selectedStrokeIds,
          );
    }

    final rect = _selectionRect!;
    final cacheKey =
        _smeltCacheKeyFor(_selectedStrokeIds, textIds: _selectedTextIds);
    final notifier = ref.read(smeltProvider.notifier);
    final selectedText = _selectedTextPayload();
    SmeltTiming.step('resolved_selection', extra: {
      'strokes': _selectedStrokeIds.length,
      'texts': _selectedTextIds.length,
      'hasTypedText': selectedText != null && selectedText.isNotEmpty,
    });

    // Reuse a session-cached response unless the user asked to retry / verify.
    if (!forceRefresh && !forceCodeExecution && notifier.hasCached(cacheKey)) {
      notifier.restoreCached(cacheKey);
      _showSmeltPopup(rect);
      SmeltTiming.step('cache_hit_popup_shown');
      return;
    }

    setState(() => _isSmelting = true);
    notifier.startLoading(
      cacheKey: cacheKey,
      forceCodeExecution: forceCodeExecution,
    );
    SmeltTiming.step('loading_state_set');

    // Show the popup immediately so loading / retry happens in-place.
    if (_smeltPopupEntry == null) {
      _showSmeltPopup(rect);
      SmeltTiming.step('popup_shown');
    } else {
      SmeltTiming.step('popup_already_open');
    }

    // Secure-storage key read overlaps with the screenshot.
    notifier.prefetchApiKey();

    // Capture the canvas region as an image
    Uint8List? imageBytes;
    try {
      imageBytes = await _captureCanvasRegion(rect, logTiming: true);
    } catch (_) {
      // If capture fails, fall back to null (text-only mode)
      SmeltTiming.step('capture_failed');
    }

    // Send to AI (stores into session cache on success)
    await notifier.smelt(
      imageBytes: imageBytes,
      selectedText: selectedText,
      cacheKey: cacheKey,
      forceCodeExecution: forceCodeExecution,
    );
    SmeltTiming.step('notifier_smelt_returned');

    if (mounted) {
      setState(() => _isSmelting = false);
      // Don't reopen if the user dismissed mid-request — cache still saves.
      _smeltPopupEntry?.markNeedsBuild();
      SmeltTiming.step('ui_loading_cleared');
    }
  }

  /// Capture the current selection and stage it as a chat attachment.
  Future<void> _attachSelectionToChat() async {
    final rect = _selectionRect;
    if (rect == null ||
        (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty)) {
      return;
    }
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
      _selectedTextIds = {};
      _showSelectionMenu = false;
      _selectionFromDetection = false;
      _activeClusterId = null;
      _manualHintVisible = false;
    });
  }

  Future<Uint8List?> _captureCanvasRegion(
    Rect region, {
    int? maxWidth,
    bool logTiming = false,
  }) async {
    final boundary = _canvasRepaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      if (logTiming) SmeltTiming.step('capture_no_boundary');
      return null;
    }

    // Infinite mode: ink layer is screen-sized; convert world → screen first.
    final captureRegion = ref.read(pageLayoutProvider).isInfinite
        ? Rect.fromPoints(
            _toScreen(region.topLeft),
            _toScreen(region.bottomRight),
          )
        : region;

    final layerBounds = Offset.zero & boundary.size;
    final clamped = Rect.fromLTRB(
      captureRegion.left.clamp(layerBounds.left, layerBounds.right),
      captureRegion.top.clamp(layerBounds.top, layerBounds.bottom),
      captureRegion.right.clamp(layerBounds.left, layerBounds.right),
      captureRegion.bottom.clamp(layerBounds.top, layerBounds.bottom),
    );
    if (clamped.width < 1 || clamped.height < 1) {
      if (logTiming) SmeltTiming.step('capture_empty_crop');
      return null;
    }

    // 2x is cheap once we snapshot only the selection, not the 5000px sheet.
    const pixelRatio = 2.0;
    if (logTiming) {
      SmeltTiming.step('capture_toImage_start', extra: {
        'pixelRatio': pixelRatio,
        'regionW': clamped.width.round(),
        'regionH': clamped.height.round(),
      });
    }

    ui.Image image;
    try {
      final layer = boundary.layer;
      if (layer is OffsetLayer) {
        image = await layer.toImage(clamped, pixelRatio: pixelRatio);
      } else {
        image = await _snapshotThenCrop(boundary, clamped, pixelRatio);
      }
    } catch (_) {
      try {
        image = await _snapshotThenCrop(boundary, clamped, pixelRatio);
        if (logTiming) SmeltTiming.step('capture_toImage_fallback');
      } catch (_) {
        if (logTiming) SmeltTiming.step('capture_toImage_failed');
        return null;
      }
    }
    if (logTiming) {
      SmeltTiming.step('capture_toImage_done', extra: {
        'width': image.width,
        'height': image.height,
      });
    }

    final imageWidth = image.width;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (logTiming) {
      SmeltTiming.step('capture_png_encode_done', extra: {
        'bytes': byteData?.lengthInBytes ?? 0,
      });
    }
    image.dispose();
    if (byteData == null) return null;

    Uint8List bytes = byteData.buffer.asUint8List();

    // Optionally downscale for chat attachments (keeps DB/base64 size sane).
    final needsDownscale = maxWidth != null && imageWidth > maxWidth;
    final needsCompress = bytes.length > 1024 * 1024;

    if (needsDownscale || needsCompress) {
      if (logTiming) {
        SmeltTiming.step('capture_local_compress_start', extra: {
          'needsDownscale': needsDownscale,
          'needsCompress': needsCompress,
          'bytes': bytes.length,
        });
      }
      final targetW = needsDownscale ? maxWidth : (imageWidth * 0.5).round();
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
      if (logTiming) {
        SmeltTiming.step('capture_local_compress_done', extra: {
          'bytes': bytes.length,
        });
      }
    }

    if (logTiming) {
      SmeltTiming.step('capture_complete', extra: {'bytes': bytes.length});
    }
    return bytes;
  }

  /// Fallback when [OffsetLayer] is not available: rasterize the full
  /// boundary, then crop. Avoid this path — it is the 2800×10000 screenshot.
  Future<ui.Image> _snapshotThenCrop(
    RenderRepaintBoundary boundary,
    Rect localRect,
    double pixelRatio,
  ) async {
    final full = await boundary.toImage(pixelRatio: pixelRatio);
    final crop = Rect.fromLTWH(
      localRect.left * pixelRatio,
      localRect.top * pixelRatio,
      localRect.width * pixelRatio,
      localRect.height * pixelRatio,
    );
    final clamped = Rect.fromLTWH(
      crop.left.clamp(0.0, full.width.toDouble()),
      crop.top.clamp(0.0, full.height.toDouble()),
      math.min(crop.width, full.width - crop.left).roundToDouble(),
      math.min(crop.height, full.height - crop.top).roundToDouble(),
    );
    try {
      if (clamped.width < 1 || clamped.height < 1) {
        throw StateError('empty crop');
      }
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        full,
        clamped,
        Rect.fromLTWH(0, 0, clamped.width, clamped.height),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      return picture.toImage(clamped.width.round(), clamped.height.round());
    } finally {
      full.dispose();
    }
  }

  void _showSmeltPopup(Rect selectionRect) {
    _smeltPopupEntry?.remove();
    if (_showSelectionMenu) {
      _showSelectionMenu = false;
    }

    final globalRect = _convertToGlobalRect(selectionRect);
    ScrapFeedback.action();

    _smeltPopupEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (ref.read(smeltGuideProvider).locksSmeltPopup) return;
                  _dismissSmeltPopup();
                },
                child: const SizedBox.expand(),
              ),
            ),
            SmeltPopup(
              key: _smeltPopupKey,
              selectionRect: globalRect,
              onDismiss: _removeSmeltPopup,
              onCollapse: _collapseSmeltPopup,
              onTryAnotherModel: _tryAnotherModelFromSmelt,
              onTapeOntoScrap: _tapeSmeltOntoScrap,
              screenSize: screenSize,
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_smeltPopupEntry!);
    // Rebuild canvas overlays so the action menu hides while popup is open.
    if (mounted) setState(() {});
  }

  void _tapeSmeltOntoScrap(SmeltResponse response) {
    final sel = _selectionRect ?? const Rect.fromLTWH(72, 72, 80, 48);
    ref.read(canvasTextNodesProvider.notifier).add(
          CanvasTextItem(
            id: const Uuid().v4(),
            position: Offset(sel.right + 18, sel.top),
            text: response.answer,
            tapedSteps: response.steps,
            taped: true,
            fontSize: 14,
          ),
        );
    ScrapFeedback.action();
    if (mounted) showPaperToast(context, 'Taped onto scrap');
  }

  Future<void> _maybeShowSmeltHint() async {
    if (ref.read(smeltGuideProvider).isActive) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('smelt_tool_hint_seen') == true) return;
    await prefs.setBool('smelt_tool_hint_seen', true);
    if (!mounted) return;
    setState(() => _smeltHintVisible = true);
    _smeltHintTimer?.cancel();
    _smeltHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _smeltHintVisible = false);
    });
  }

  void _dismissSmeltPopup() {
    _clearSelectionState();
    final state = _smeltPopupKey.currentState;
    if (state != null) {
      state.dismiss();
      return;
    }
    _removeSmeltPopup();
  }

  void _collapseSmeltPopup() {
    _smeltPopupEntry?.remove();
    _smeltPopupEntry = null;
    if (mounted) setState(() {});
  }

  Future<void> _tryAnotherModelFromSmelt() async {
    final rect = _selectionRect;
    if (rect == null) return;

    final smelt = ref.read(smeltProvider);
    final currentModel =
        smelt.response?.modelUsed ?? ref.read(chatModelProvider);

    final popupState = _smeltPopupKey.currentState;
    if (popupState != null) {
      await popupState.collapse();
    } else {
      _collapseSmeltPopup();
    }

    if (!mounted) return;

    final selected = await showModelPickerSheet(
      context,
      oneTime: true,
      selectedModelId: currentModel,
      showCodeOption: true,
    );

    if (!mounted) return;

    if (selected == null) {
      _showSmeltPopup(rect);
      return;
    }

    final sameModel = selected.modelId == currentModel;
    if (sameModel && !selected.forceCodeExecution) {
      _showSmeltPopup(rect);
      return;
    }

    ref.read(smeltProvider.notifier).startLoading(
          forceCodeExecution: selected.forceCodeExecution,
        );
    _showSmeltPopup(rect);
    SmeltTiming.begin(extra: {
      'source': 'canvas_retry',
      'model': selected.modelId,
      'forceCodeExecution': selected.forceCodeExecution,
    });
    await ref.read(smeltProvider.notifier).retry(
          preferredModel: selected.modelId,
          singleModel: true,
          forceCodeExecution: selected.forceCodeExecution,
        );
    SmeltTiming.step('retry_returned');
    if (mounted) {
      _smeltPopupEntry?.markNeedsBuild();
    }
  }

  void _removeSmeltPopup() {
    _smeltPopupEntry?.remove();
    _smeltPopupEntry = null;
    ref.read(smeltProvider.notifier).clearState();
    if (!mounted) return;
    // Outside-tap / close should drop the highlight too — otherwise a second
    // tap is needed just to dismiss the bounding box.
    _clearSelectionState();
    setState(() {});
  }

  void _deleteSelection() {
    if (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty) return;
    _hideSelectionMenu();
    if (_selectedStrokeIds.isNotEmpty) {
      ref
          .read(strokesProvider.notifier)
          .deleteStrokes(_selectedStrokeIds.toList());
    }
    if (_selectedTextIds.isNotEmpty) {
      ref.read(canvasTextNodesProvider.notifier).deleteIds(_selectedTextIds);
    }
    setState(() {
      _selectionRect = null;
      _selectedStrokeIds = {};
      _selectedTextIds = {};
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
    if (_selectedStrokeIds.isEmpty && _selectedTextIds.isEmpty) {
      setState(() {
        _selectionRect = null;
        _showSelectionMenu = false;
        _isResizingSelection = false;
      });
      return;
    }

    final strokes = ref.read(strokesProvider);
    final selected =
        strokes.where((stroke) => _selectedStrokeIds.contains(stroke.id)).toList();
    final textNodes = ref
        .read(canvasTextNodesProvider)
        .where((n) => _selectedTextIds.contains(n.id))
        .toList();

    if (selected.isEmpty && textNodes.isEmpty) {
      setState(() {
        _selectionRect = null;
        _selectedStrokeIds = {};
        _selectedTextIds = {};
        _showSelectionMenu = false;
        _isResizingSelection = false;
      });
      return;
    }

    final boundRects = <Rect>[
      ...selected.map((stroke) => _strokeBounds(stroke).inflate(4)),
      ...textNodes.map((n) => _textItemBounds(n).inflate(4)),
    ];
    final bounds = _unionRects(boundRects);
    setState(() {
      _selectionRect = bounds;
      _showSelectionMenu = showMenu;
      _isResizingSelection = false;
    });
  }

  void _handleCanvasLongPressStart(LongPressStartDetails details) {
    if (_tapedSlipOwnsPointer()) return;
    if (_clipboardSelection == null) return;
    _showPasteMenuAt(_toWorld(details.localPosition));
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
      if (!_refSafe) return;
      if (previous != null && next.length > previous.length) _triggerOcrRun();
    });

    ref.listen<String?>(activeTextNodeIdProvider, (previous, next) {
      if (!_refSafe) return;
      if (next != null) {
        _revealActiveTextAboveKeyboard();
      } else {
        ref.read(activeTextGlobalRectProvider.notifier).state = null;
      }
    });

    ref.listen<Rect?>(activeTextGlobalRectProvider, (previous, next) {
      if (!_refSafe) return;
      if (next != null &&
          ref.read(activeTextNodeIdProvider) != null &&
          MediaQuery.viewInsetsOf(context).bottom > 0) {
        _revealActiveTextAboveKeyboard();
      }
    });

    ref.listen<CanvasTool>(activeCanvasToolProvider, (previous, next) {
      if (!_refSafe) return;
      if (previous == CanvasTool.text && next != CanvasTool.text) {
        ref.read(activeTextNodeIdProvider.notifier).state = null;
      }
      if (next == CanvasTool.smelt && previous != CanvasTool.smelt) {
        _maybeShowSmeltHint();
      }
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
      if (!_refSafe) return;
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
          _selectedTextIds = {};
          _showSelectionMenu = false;
          _isResizingSelection = false;
          _selectionFromDetection = false;
          _activeClusterId = null;
          _manualSelectMenuAnchor = null;
          _manualHintVisible = true;
        });
        _manualHintTimer = Timer(const Duration(seconds: 3), () {
          if (!_refSafe) return;
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
      if (!_refSafe) return;
      if (next == true &&
          _chatCaptureMode &&
          ref.read(pendingChatAttachmentProvider) == null) {
        ref.read(chatCaptureRequestProvider.notifier).state = false;
      }
    });

    ref.listen<InkCalculatorState>(inkCalculatorProvider, (previous, next) {
      if (!_refSafe) return;
      if (_inkCalcPopupEntry == null) return;
      final noteId = ref.read(activeNoteIdProvider);
      if (next.resultsFor(noteId).isEmpty) {
        _dismissInkCalcPopup();
      }
    });

    ref.listen<bool>(stylusOnlyModeProvider, (previous, next) {
      if (next && _refSafe) {
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

    ref.listen<List<OpenedTab>>(openedTabsProvider, (previous, next) {
      if (!widget.ownsRoute) return;
      if (next.isEmpty && (previous == null || previous.isNotEmpty)) {
        // Defer: discard can run while a dialog route is still unlocking.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
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
    final pageLayout      = ref.watch(pageLayoutProvider);
    final isInfinite      = pageLayout.isInfinite;
    final canvasZoom      = isInfinite
        ? ref.watch(canvasViewportProvider).scale
        : ref.watch(canvasZoomProvider);
    final toolbarPosition = ref.watch(toolbarPositionProvider);
    ref.watch(canvasHistoryCoordinatorProvider);

    final strokes = ref.watch(strokesProvider);

    final activeNoteId = ref.watch(activeNoteIdProvider);
    final isLooseScrap = ref
        .watch(ephemeralNoteIdsProvider)
        .contains(activeNoteId) &&
        !ref.watch(pendingNewScrapsProvider).containsKey(activeNoteId);
    final guideActive = ref.watch(smeltGuideProvider).isActive &&
        ref.watch(smeltGuideProvider).step.isEditorStep;
    final hideFreshHint = guideActive;

    final selectionReady = _showSelectionMenu && isSmeltMode;
    final prevReady = ref.read(smeltGuideSelectionReadyProvider);
    if (prevReady != selectionReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(smeltGuideSelectionReadyProvider) != selectionReady) {
          ref.read(smeltGuideSelectionReadyProvider.notifier).state =
              selectionReady;
        }
      });
    }

    final calcState = ref.watch(inkCalculatorProvider);
    final debugGuess = kDebugMode ? calcState.debugGuess : null;
    final worldAnnotations = <Widget>[
      if (strokes.isEmpty && !isInfinite && !hideFreshHint)
        Positioned(
          top: 80,
          left: 0,
          right: 0,
          child: _FreshScrapHint(
            ephemeral: isLooseScrap,
          ),
        ),
      ...ref.watch(canvasTextNodesProvider).map(
            (node) => node.taped
                ? TapedSlipOverlay(key: ValueKey(node.id), item: node)
                : CanvasTextSticker(key: ValueKey(node.id), item: node),
          ),
      ...ref
          .watch(canvasTablesProvider)
          .map((t) => CanvasTableOverlay(table: t)),
      ...calcState.resultsFor(ref.watch(activeNoteIdProvider)).map(
            (calc) => InkCalculatorAnswerOverlay(
              key: ValueKey(calc.pairKey),
              result: calc,
            ),
          ),
      if (debugGuess != null)
        Positioned(
          left: debugGuess.bounds.left,
          top: debugGuess.bounds.top,
          width: debugGuess.bounds.width,
          height: debugGuess.bounds.height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xE0C45C26),
                  width: 2,
                ),
                color: const Color(0x22C45C26),
              ),
            ),
          ),
        ),
    ];

    // Finite sheet only — avoid building a second HandwritingCanvas (and moving
    // [_canvasRepaintKey]) while infinite mode is active.
    final Widget? canvasStack = isInfinite
        ? null
        : RepaintBoundary(
            key: _canvasRepaintKey,
            child: Stack(
              children: [
                HandwritingCanvas(
                  scrollController: _scrollController,
                  horizontalScrollController: _horizontalScrollController,
                  zoomLevel: canvasZoom,
                  onZoomChanged: (v) =>
                      ref.read(canvasZoomProvider.notifier).state = v,
                  suppressTouchScroll: _isMovingSelection,
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: PaperGrain(opacity: 0.022),
                    ),
                  ),
                ),
                ...worldAnnotations,
              ],
            ),
          );

    // Lasso/selection/paste overlays. In infinite mode these are converted to
    // screen space so they aren't clipped by a screen-sized Stack.
    Offset overlayPos(Offset world) => isInfinite ? _toScreen(world) : world;
    Rect? overlayRect(Rect? world) {
      if (world == null) return null;
      if (!isInfinite) return world;
      return Rect.fromPoints(
        _toScreen(world.topLeft),
        _toScreen(world.bottomRight),
      );
    }

    final List<Widget> contentOverlays = [];
    final lassoScreen = overlayRect(_lassoPreviewRect);
    if (lassoScreen != null) {
      contentOverlays.add(
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LassoPainter(lassoScreen),
            ),
          ),
        ),
      );
    }
    final selectionScreen = overlayRect(_selectionRect);
    if (selectionScreen != null && _selectionRect != null) {
      contentOverlays.add(
        Positioned.fill(
          child: Stack(
            children: [
              _SelectionBoxHighlight(
                key: ValueKey(_activeClusterId ?? 'selection'),
                rect: selectionScreen,
                fromDetection: _selectionFromDetection,
                isSmelting: _isSmelting,
              ),
              if (!_isResizingSelection &&
                  !_isSmelting &&
                  _inkCalcPopupEntry == null)
                Positioned.fromRect(
                  rect: selectionScreen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _hideSelectionMenu();
                      _hidePasteMenu();
                      _lastSelectionDragGlobal = details.globalPosition;
                      _lastEdgeScrollTickPointer = null;
                      setState(() => _isMovingSelection = true);
                      _startSelectionEdgeScrollTimer(canvasZoom);
                    },
                    onPanUpdate: (details) {
                      final prevGlobal =
                          _lastSelectionDragGlobal ?? details.globalPosition;
                      final globalDelta =
                          details.globalPosition - prevGlobal;
                      final canvasDelta = _globalDeltaToCanvas(globalDelta);
                      _handleSelectionDrag(
                        canvasDelta,
                        details.globalPosition,
                        canvasZoom,
                      );
                    },
                    onPanEnd: (_) {
                      _stopSelectionEdgeScrollTimer();
                      _lastSelectionDragGlobal = null;
                      _finishSelectionMove();
                      setState(() => _isMovingSelection = false);
                    },
                    onPanCancel: () {
                      _stopSelectionEdgeScrollTimer();
                      _lastSelectionDragGlobal = null;
                      setState(() => _isMovingSelection = false);
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              if (_isResizingSelection) ...[
                _SelectionCornerHandle(
                  rect: selectionScreen,
                  cornerIndex: 0,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(
                    0,
                    isInfinite ? Offset(delta.dx / canvasZoom, delta.dy / canvasZoom) : delta,
                  ),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: selectionScreen,
                  cornerIndex: 1,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(
                    1,
                    isInfinite ? Offset(delta.dx / canvasZoom, delta.dy / canvasZoom) : delta,
                  ),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: selectionScreen,
                  cornerIndex: 2,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(
                    2,
                    isInfinite ? Offset(delta.dx / canvasZoom, delta.dy / canvasZoom) : delta,
                  ),
                  onPanEnd: _finishResizeSelection,
                ),
                _SelectionCornerHandle(
                  rect: selectionScreen,
                  cornerIndex: 3,
                  onPanStart: _beginResizeSelection,
                  onPanUpdate: (delta) => _resizeSelection(
                    3,
                    isInfinite ? Offset(delta.dx / canvasZoom, delta.dy / canvasZoom) : delta,
                  ),
                  onPanEnd: _finishResizeSelection,
                ),
              ],
              if (_showSelectionMenu &&
                  (isSmeltMode || _selectionFromDetection) &&
                  _smeltActionMenuAllowed)
                SmeltActionMenu(
                  rect: selectionScreen,
                  showManualSelect: _selectionFromDetection,
                  onSmelt: () => _smeltSelection(),
                  onSmeltWithCode: () =>
                      _smeltSelection(forceCodeExecution: true),
                  onAddToChat: _attachSelectionToChat,
                  onManualSelect: _beginManualSelect,
                )
              else if (_showSelectionMenu &&
                  !isSmeltMode &&
                  !_selectionFromDetection)
                _SelectionActionMenu(
                  rect: selectionScreen,
                  onResize: _beginResizeSelection,
                  onDelete: _deleteSelection,
                  onCopy: _copySelection,
                ),
            ],
          ),
        ),
      );
    }
    if (_smeltHintVisible && !guideActive) {
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
                    'Lasso or tap a cluster',
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
      final anchor = overlayPos(_manualSelectMenuAnchor!);
      contentOverlays.add(
        Positioned(
          left: math.max(anchor.dx, 12.0),
          top: math.max(anchor.dy - 52, 12.0),
          child: _ManualSelectActionMenu(onSelect: _beginManualSelect),
        ),
      );
    }
    if (_showPasteMenu && _pasteMenuAnchor != null) {
      final anchor = overlayPos(_pasteMenuAnchor!);
      contentOverlays.add(
        Positioned(
          left: anchor.dx,
          top: anchor.dy,
          child: _PasteMenu(
            onPaste: () => _pasteClipboard(_pasteMenuAnchor!),
          ),
        ),
      );
    }

    // Plain Stack — callers wrap in Expanded as needed (never nest Expanded).
    final scrollPhysics = (isSelectionMode || isPenMode)
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    final Widget canvasBody;
    if (isInfinite) {
      canvasBody = InfiniteCanvasSurface(
        inkRepaintKey: _canvasRepaintKey,
        worldOverlays: worldAnnotations,
        screenOverlays: contentOverlays,
        suppressTouchScroll: _isMovingSelection,
        onPointerDown: stylusOnly ? _onSelectionPointerDown : null,
        onPointerMove: stylusOnly ? _onSelectionPointerMove : null,
        onPointerUp: stylusOnly ? _onSelectionPointerUp : null,
        onPointerCancel: stylusOnly ? _onSelectionPointerCancel : null,
        onTapDown: _onCanvasTapDown,
        onTapUp: isSmeltMode ? _onCanvasTapUp : null,
        onLongPressStart: _handleCanvasLongPressStart,
        onPanStart: allowSelectionDrag ? _startLasso : null,
        onPanUpdate: allowSelectionDrag ? _updateLasso : null,
        onPanEnd: allowSelectionDrag ? _endLasso : null,
      );
    } else {
      canvasBody = LayoutBuilder(
        builder: (context, constraints) {
          final viewportW = constraints.maxWidth;
          final zoom = canvasZoom;
          final scaledW = viewportW * zoom;
          final scaledH = 5000 * zoom;
          final contentW = math.max(viewportW, scaledW);

          final page = SizedBox(
            width: scaledW,
            height: scaledH,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: viewportW,
              maxWidth: viewportW,
              minHeight: 5000,
              maxHeight: 5000,
              child: Transform.scale(
                scale: zoom,
                alignment: Alignment.topLeft,
                child: DecoratedBox(
                  decoration: zoom <= 1.0
                      ? const BoxDecoration(boxShadow: ScrapTheme.subtleShadow)
                      : const BoxDecoration(),
                  child: SizedBox(
                    width: viewportW,
                    height: 5000,
                    child: Listener(
                      onPointerDown:
                          stylusOnly ? _onSelectionPointerDown : null,
                      onPointerMove:
                          stylusOnly ? _onSelectionPointerMove : null,
                      onPointerUp: stylusOnly ? _onSelectionPointerUp : null,
                      onPointerCancel:
                          stylusOnly ? _onSelectionPointerCancel : null,
                      child: GestureDetector(
                        onTapDown: _onCanvasTapDown,
                        onTapUp: isSmeltMode ? _onCanvasTapUp : null,
                        onLongPressStart: _handleCanvasLongPressStart,
                        onPanStart: allowSelectionDrag ? _startLasso : null,
                        onPanUpdate: allowSelectionDrag ? _updateLasso : null,
                        onPanEnd: allowSelectionDrag ? _endLasso : null,
                        child: Stack(
                          children: [
                            canvasStack!,
                            ...contentOverlays,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          return SingleChildScrollView(
            controller: _scrollController,
            physics: scrollPhysics,
            child: ColoredBox(
              color: zoom <= 1.0
                  ? ScrapTheme.codeSurface
                  : ScrapTheme.background,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                physics: scrollPhysics,
                child: SizedBox(
                  width: contentW,
                  height: scaledH,
                  child: zoom < 1.0
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: page,
                        )
                      : page,
                ),
              ),
            ),
          );
        },
      );
    }

    final canvasSurface = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          canvasBody,
          // Screen-anchored empty hint for infinite mode
          if (isInfinite && strokes.isEmpty && !hideFreshHint)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _FreshScrapHint(
                  ephemeral: isLooseScrap,
                ),
              ),
            ),
          if (debugGuess != null)
            Positioned.fill(
              child: InkCalculatorDebugPopup(
                guess: debugGuess,
                onDismiss: () {
                  ref.read(inkCalculatorProvider.notifier).clearDebugGuess();
                },
              ),
            ),
          // AI chat FAB — bottom right (skipped when parent hosts chat chrome)
          if (widget.showChatChrome)
            const Positioned(
              right: 16,
              bottom: 16,
              child: CanvasSmartBar(),
            ),
        ],
      ),
    );

    Widget toolSurface;
    switch (toolbarPosition) {
      case ToolbarPosition.top:
        toolSurface = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Material(
              color: ScrapTheme.cardSurface,
              elevation: 1,
              child: CanvasToolbar(),
            ),
            Expanded(child: canvasSurface),
          ],
        );
        break;
      case ToolbarPosition.bottom:
        toolSurface = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: canvasSurface),
            const Material(
              color: ScrapTheme.cardSurface,
              elevation: 1,
              child: SafeArea(top: false, child: CanvasToolbar()),
            ),
          ],
        );
        break;
      case ToolbarPosition.left:
        toolSurface = SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Material(
                color: ScrapTheme.cardSurface,
                elevation: 1,
                child: CanvasToolbar(),
              ),
              Expanded(child: canvasSurface),
            ],
          ),
        );
        break;
      case ToolbarPosition.right:
        toolSurface = SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: canvasSurface),
              const Material(
                color: ScrapTheme.cardSurface,
                elevation: 1,
                child: CanvasToolbar(),
              ),
            ],
          ),
        );
        break;
    }

    final overlayChat = widget.showChatChrome &&
        ScrapLayout.of(context).usesChatOverlay;

    Widget editorColumn = Column(
      children: [
        const SafeArea(bottom: false, child: DocumentTabBar()),
        Expanded(child: toolSurface),
      ],
    );

    Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: editorColumn),
        if (widget.showChatChrome && !overlayChat) const AiChatPanel(),
      ],
    );

    if (overlayChat) {
      body = Stack(
        children: [
          Positioned.fill(child: body),
          const AiChatPanel(overlay: true),
        ],
      );
    }

    final scaffold = Scaffold(
      backgroundColor: ScrapTheme.background,
      // Keep full canvas height; we pan/scroll text above the keyboard ourselves.
      resizeToAvoidBottomInset: false,
      body: body,
    );

    if (!widget.ownsRoute) return scaffold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (overlayChat && ref.read(chatPanelOpenProvider)) {
          ref.read(chatPanelOpenProvider.notifier).state = false;
          return;
        }
        await leaveNoteEditorIfAllowed(context, ref);
      },
      child: scaffold,
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

class _FreshScrapHint extends StatefulWidget {
  final bool ephemeral;

  const _FreshScrapHint({this.ephemeral = false});

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
            ScrapStampLabel(
              text: widget.ephemeral
                  ? '⟨ loose scrap ⟩'
                  : '⟨ fresh scrap ⟩',
              color: widget.ephemeral ? ScrapTheme.mutedText : null,
            ),
            const SizedBox(height: 10),
            Text(
              widget.ephemeral
                  ? 'scribble freely — this sheet won\'t be filed'
                  : 'scribble anything — Smelt figures it out',
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
      child: PaperChit(
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

class _ManualSelectActionMenu extends StatelessWidget {
  final VoidCallback onSelect;

  const _ManualSelectActionMenu({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PaperChit(
      child: ManualSelectButton(onTap: onSelect),
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
    return PaperMenuChip(
      label: label,
      onTap: onTap,
      tone: danger ? PaperMenuChipTone.danger : PaperMenuChipTone.secondary,
    );
  }
}

class _PasteMenu extends StatelessWidget {
  final VoidCallback onPaste;

  const _PasteMenu({required this.onPaste});

  @override
  Widget build(BuildContext context) {
    return PaperChit(
      child: PaperMenuChip(
        label: 'Paste',
        onTap: onPaste,
        tone: PaperMenuChipTone.primary,
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
