import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../providers/pdf_providers.dart';
import '../widgets/annotation_toolbar.dart';
import '../widgets/split_screen_layout.dart';
import '../widgets/annotation_layer.dart';
import '../../../canvas/presentation/screens/note_editor_screen.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  const PdfViewerScreen({super.key});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();

  // Mocked for testing, realistically we pick a file
  final String _mockDocId = 'test-doc-id-1234';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pdfDocumentIdProvider.notifier).state = _mockDocId;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSplitScreen = ref.watch(isSplitScreenProvider);

    return Scaffold(
      backgroundColor: ScrapTheme.cardSurface,
      appBar: AppBar(
        backgroundColor: ScrapTheme.background,
        elevation: 0,
        title: Text(
          'Document',
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
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: ScrapMotion.panel,
            switchInCurve: ScrapMotion.panelCurve,
            switchOutCurve: ScrapMotion.exitCurve,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: isSplitScreen
                ? SplitScreenLayout(
                    key: const ValueKey('split'),
                    leftChild: _buildPdfViewer(),
                    rightChild:
                        const NoteEditorScreen(), // Phase 4 placeholder inside split
                  )
                : KeyedSubtree(
                    key: const ValueKey('single'),
                    child: _buildPdfViewer(),
                  ),
          ),

          // Draggable formatting pill
          const AnnotationToolbar(),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    return PdfViewer.asset(
      'assets/sample.pdf', // Requires adding a default asset or switching to empty state
      controller: _pdfController,
      params: PdfViewerParams(
        backgroundColor: ScrapTheme.codeSurface,
        // Custom page processing can be added here
        viewerOverlayBuilder: (context, size, params) {
          return [
            // Overlaying a generic annotation canvas since pdf pages handle scrolling.
            // Using pdfrx, annotations can be painted in viewerOverlayBuilder.
            // Here we overlay above the entire viewer for freehand drawing.
            // Full integration maps page coords via PdfViewer params.
            Positioned.fill(
              child: AnnotationLayer(
                pageNumber: 1, // Simplified for now
                documentId: _mockDocId,
              ),
            ),
          ];
        },
      ),
    );
  }
}
