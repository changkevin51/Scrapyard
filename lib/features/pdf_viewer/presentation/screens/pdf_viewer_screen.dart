import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../core/gestures/pan_fling.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_chat/presentation/widgets/ai_chat_panel.dart';
import '../../../ai_engine/presentation/widgets/smelt_action_menu.dart';
import '../../../ai_engine/presentation/widgets/smelt_popup.dart';
import '../../../canvas/presentation/screens/note_editor_screen.dart';
import '../../../canvas/presentation/widgets/canvas_smart_widgets.dart';
import '../providers/pdf_providers.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/split_screen_layout.dart';
import '../widgets/annotation_layer.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen>
    with TickerProviderStateMixin {
  final PdfViewerController _pdfController = PdfViewerController();
  late final PanFling _panFling;
  final GlobalKey<SmeltPopupState> _smeltPopupKey = GlobalKey<SmeltPopupState>();
  OverlayEntry? _smeltPopupEntry;
  OverlayEntry? _smeltMenuEntry;
  Future<void> Function({bool forceRefresh, bool forceCodeExecution})?
      _activeSmeltRunner;
  Future<Uint8List?> Function()? _captureSelection;
  Rect? _menuSelectionRect;

  @override
  void initState() {
    super.initState();
    _panFling = PanFling(
      vsync: this,
      onPanDelta: (delta) {
        if (!_pdfController.isReady) return;
        final m = _pdfController.value.clone();
        m.xZoomed += delta.dx;
        m.yZoomed += delta.dy;
        _pdfController.value = m;
      },
    );
  }

  @override
  void dispose() {
    _panFling.dispose();
    _smeltPopupEntry?.remove();
    _smeltMenuEntry?.remove();
    _smeltPopupEntry = null;
    _smeltMenuEntry = null;
    super.dispose();
  }

  void _showSmeltActionMenu(Rect selectionRect) {
    _smeltMenuEntry?.remove();
    _menuSelectionRect = selectionRect;
    ScrapFeedback.tap();

    _smeltMenuEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissSmeltMenu,
                child: const SizedBox.expand(),
              ),
            ),
            // Same scrap SmeltActionMenu — positioned above the selection.
            SmeltActionMenu(
              rect: selectionRect,
              onSmelt: () => _runSmeltFromMenu(forceCodeExecution: false),
              onSmeltWithCode: () =>
                  _runSmeltFromMenu(forceCodeExecution: true),
              onAddToChat: _attachSelectionToChat,
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_smeltMenuEntry!);
  }

  void _dismissSmeltMenu() {
    _smeltMenuEntry?.remove();
    _smeltMenuEntry = null;
    ref.read(pdfSmeltRectProvider.notifier).state = null;
    _menuSelectionRect = null;
    _captureSelection = null;
  }

  Future<void> _attachSelectionToChat() async {
    final capture = _captureSelection;
    _smeltMenuEntry?.remove();
    _smeltMenuEntry = null;

    Uint8List? bytes;
    try {
      bytes = await capture?.call();
    } catch (_) {}

    if (!mounted) return;
    if (bytes != null) {
      ref.read(pendingChatAttachmentProvider.notifier).state = bytes;
      // Open chat beside the PDF — do not force the scrap split on.
      ref.read(chatPanelOpenProvider.notifier).state = true;
    }
    ref.read(pdfSmeltRectProvider.notifier).state = null;
    _menuSelectionRect = null;
    _captureSelection = null;
    _activeSmeltRunner = null;
  }

  Future<void> _runSmeltFromMenu({required bool forceCodeExecution}) async {
    final runner = _activeSmeltRunner;
    final rect = _menuSelectionRect;
    if (runner == null || rect == null) return;

    _smeltMenuEntry?.remove();
    _smeltMenuEntry = null;

    _showSmeltPopup(rect);
    await runner(forceCodeExecution: forceCodeExecution);
    _smeltPopupEntry?.markNeedsBuild();
  }

  void _showSmeltPopup(Rect selectionRect) {
    _smeltPopupEntry?.remove();
    ScrapFeedback.action();

    _smeltPopupEntry = OverlayEntry(
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissSmeltPopup,
                child: const SizedBox.expand(),
              ),
            ),
            SmeltPopup(
              key: _smeltPopupKey,
              selectionRect: selectionRect,
              onDismiss: _removeSmeltPopup,
              onCollapse: _removeSmeltPopup,
              onTryAnotherModel: _tryAnotherModelFromSmelt,
              screenSize: screenSize,
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_smeltPopupEntry!);
  }

  void _removeSmeltPopup() {
    _smeltPopupEntry?.remove();
    _smeltPopupEntry = null;
    _activeSmeltRunner = null;
    _captureSelection = null;
    ref.read(pdfSmeltRectProvider.notifier).state = null;
    _menuSelectionRect = null;
  }

  void _dismissSmeltPopup() {
    _removeSmeltPopup();
  }

  Future<void> _tryAnotherModelFromSmelt() async {
    final runner = _activeSmeltRunner;
    if (runner == null) return;
    await runner(forceRefresh: true);
    _smeltPopupEntry?.markNeedsBuild();
  }

  void _onSmeltSelection({
    required Rect selectionRect,
    required Future<void> Function({
      bool forceRefresh,
      bool forceCodeExecution,
    }) runSmelt,
    required Future<Uint8List?> Function() captureSelection,
  }) {
    _activeSmeltRunner = runSmelt;
    _captureSelection = captureSelection;
    _showSmeltActionMenu(selectionRect);
  }

  @override
  Widget build(BuildContext context) {
    final isSplitScreen = ref.watch(isSplitScreenProvider);
    final pdfPath = ref.watch(activePdfPathProvider);
    final pdfTitle = ref.watch(activePdfTitleProvider);
    final documentId = ref.watch(pdfDocumentIdProvider);

    return Scaffold(
      backgroundColor: ScrapTheme.cardSurface,
      appBar: AppBar(
        backgroundColor: ScrapTheme.background,
        elevation: 0,
        title: Text(
          pdfTitle?.isNotEmpty == true ? pdfTitle! : 'Document',
          style: ScrapTextStyles.heading.copyWith(fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: ScrapTheme.primaryText),
        actions: [
          ScrapPressable(
            scale: 0.9,
            onTap: () {
              ScrapFeedback.tap();
              ref.read(isSplitScreenProvider.notifier).state = !isSplitScreen;
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                isSplitScreen
                    ? Icons.vertical_split
                    : Icons.vertical_split_outlined,
                color: isSplitScreen
                    ? ScrapTheme.accent
                    : ScrapTheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                // Keep a single PdfViewer mounted across split toggles.
                // AnimatedSwitcher previously created a second viewer that
                // disposed first and called controller._attach(null), killing
                // finger pan/zoom while a draw tool was active.
                SplitScreenLayout(
                  split: isSplitScreen,
                  leftChild: _buildPdfViewer(pdfPath, documentId),
                  rightChild: const NoteEditorScreen(
                    showChatChrome: false,
                    ownsRoute: false,
                  ),
                ),
                const AnnotationToolbar(),
                // Chat FAB stays available even when scrap split is off.
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: CanvasSmartBar(),
                ),
              ],
            ),
          ),
          const AiChatPanel(),
        ],
      ),
    );
  }

  Widget _buildPdfViewer(String? pdfPath, String? documentId) {
    if (pdfPath == null || pdfPath.isEmpty) {
      return const Center(
        child: Text(
          'No PDF selected',
          style: TextStyle(color: ScrapTheme.secondaryText),
        ),
      );
    }

    final docId = documentId ?? pdfPath;

    return PdfViewer.file(
      pdfPath,
      controller: _pdfController,
      params: PdfViewerParams(
        backgroundColor: ScrapTheme.codeSurface,
        pageOverlaysBuilder: (context, pageRect, page) {
          return [
            Positioned.fill(
              child: AnnotationLayer(
                pageNumber: page.pageNumber,
                documentId: docId,
                page: page,
                viewerController: _pdfController,
                panFling: _panFling,
                onSmeltSelection: _onSmeltSelection,
              ),
            ),
          ];
        },
      ),
    );
  }
}
