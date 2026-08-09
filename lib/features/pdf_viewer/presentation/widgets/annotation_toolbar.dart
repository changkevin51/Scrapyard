import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../../../core/widgets/toolbar_tool_icons.dart';
import '../../../canvas/data/pen_engine.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../../canvas/presentation/widgets/ink_color_controls.dart';
import '../providers/pdf_providers.dart';

class AnnotationToolbar extends ConsumerStatefulWidget {
  const AnnotationToolbar({super.key});

  @override
  ConsumerState<AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends ConsumerState<AnnotationToolbar> {
  bool _isExpanded = false;
  Offset _position = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isExpanded
              ? TornSheet(
                  key: const ValueKey('expanded'),
                  seed: 29,
                  edges: const {TornEdge.right},
                  amplitude: 3.5,
                  child: _buildExpandedToolbar(),
                )
              : _buildIdleTab(key: const ValueKey('idle')),
        ),
      ),
    );
  }

  Widget _buildIdleTab({Key? key}) {
    return ScrapPressable(
      key: key,
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: ScrapTheme.kraft,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: ScrapTheme.dividers, width: 0.75),
          boxShadow: ScrapTheme.deskShadow,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ScrapTheme.accent,
                  borderRadius: BorderRadius.circular(1),
                  border: Border.all(
                    color: ScrapTheme.kraft.withValues(alpha: 0.6),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedToolbar() {
    final palette = ref.watch(inkPaletteProvider);
    final activeTool = ref.watch(activeToolProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toolButton(
                tip: 'Pan',
                tool: AnnotationTool.pan,
                activeTool: activeTool,
                child: Icon(
                  Icons.pan_tool_outlined,
                  size: 24,
                  color: _toolColor(activeTool == AnnotationTool.pan),
                ),
              ),
              _toolButton(
                tip: 'Pen',
                tool: AnnotationTool.pen,
                activeTool: activeTool,
                child: Icon(
                  Icons.edit_outlined,
                  size: 24,
                  color: _toolColor(activeTool == AnnotationTool.pen),
                ),
              ),
              _toolButton(
                tip: 'Highlighter',
                tool: AnnotationTool.highlighter,
                activeTool: activeTool,
                child: HighlighterIcon(
                  size: 24,
                  color: _toolColor(activeTool == AnnotationTool.highlighter),
                ),
              ),
              _toolButton(
                tip: 'Eraser',
                tool: AnnotationTool.eraser,
                activeTool: activeTool,
                child: EraserIcon(
                  size: 24,
                  color: _toolColor(activeTool == AnnotationTool.eraser),
                ),
              ),
              _toolButton(
                tip: 'Smelt',
                tool: AnnotationTool.smelt,
                activeTool: activeTool,
                child: Icon(
                  Icons.auto_awesome,
                  size: 24,
                  color: _toolColor(activeTool == AnnotationTool.smelt),
                ),
              ),
              const SizedBox(width: 8),
              PaperIconButton(
                icon: Icons.close,
                color: ScrapTheme.mutedText,
                iconSize: 20,
                onPressed: () {
                  // Collapsing tools returns to pan/touch so the PDF stays
                  // scrollable without an invisible draw tool still active.
                  ref.read(activeToolProvider.notifier).state =
                      AnnotationTool.pan;
                  setState(() => _isExpanded = false);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < palette.length; i++)
                InkColorDot(color: palette[i], index: i, pdfMode: true),
            ],
          ),
        ],
      ),
    );
  }

  Color _toolColor(bool active) =>
      active ? ScrapTheme.primaryText : ScrapTheme.mutedText;

  void _selectTool(AnnotationTool tool) {
    ref.read(activeToolProvider.notifier).state = tool;
    if (tool == AnnotationTool.pen) {
      ref.read(activeInkFamilyProvider.notifier).state = InkFamily.pen;
      restoreToolColor(ref, CanvasTool.pen);
    } else if (tool == AnnotationTool.highlighter) {
      ref.read(activeInkFamilyProvider.notifier).state = InkFamily.highlighter;
      restoreToolColor(ref, CanvasTool.highlighter);
    }
  }

  Widget _toolButton({
    required String tip,
    required AnnotationTool tool,
    required AnnotationTool activeTool,
    required Widget child,
  }) {
    final isActive = activeTool == tool;

    return Tooltip(
      message: tip,
      child: ScrapPressable(
        onTap: () => _selectTool(tool),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              child,
              if (isActive) ...[
                const SizedBox(height: 4),
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: ScrapTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
