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
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: isPenMode
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                width: double.infinity,
                height: 5000,
                child: canvasStack,
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
