import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../providers/pdf_providers.dart';

class AnnotationToolbar extends ConsumerStatefulWidget {
  const AnnotationToolbar({super.key});

  @override
  ConsumerState<AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends ConsumerState<AnnotationToolbar> {
  bool _isExpanded = false;
  Offset _position = const Offset(20, 100);

  // Colors: Ink (#1C1C1C), Brown (#6B4C3B), Pencil (#4A4A4A)
  // Highlight: Amber, Sage, Rose, Slate blue
  final List<Color> _palette = [
    const Color(0xFF1C1C1C),
    const Color(0xFF6B4C3B),
    const Color(0xFF4A4A4A),
    const Color(0x66E8C547), // 40% Amber
    const Color(0x598BAF7A), // 35% Sage
    const Color(0x59C49A8A), // 35% Rose
    const Color(0x597A9BB5), // 35% Slate
  ];

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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolIcon(Icons.pan_tool_outlined, AnnotationTool.pan),
              _buildToolIcon(Icons.highlight_outlined, AnnotationTool.highlight),
              _buildToolIcon(Icons.edit_outlined, AnnotationTool.ink),
              _buildToolIcon(Icons.chat_bubble_outline, AnnotationTool.comment),
              _buildToolIcon(Icons.crop_square_outlined, AnnotationTool.shape),
              const SizedBox(width: 8),
              PaperIconButton(
                icon: Icons.close,
                color: ScrapTheme.mutedText,
                iconSize: 20,
                onPressed: () => setState(() => _isExpanded = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _palette.map((color) => _buildColorCircle(color)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolIcon(IconData icon, AnnotationTool tool) {
    final activeTool = ref.watch(activeToolProvider);
    final isActive = activeTool == tool;

    return ScrapPressable(
      onTap: () => ref.read(activeToolProvider.notifier).state = tool,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: isActive ? ScrapTheme.primaryText : ScrapTheme.mutedText,
            ),
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
    );
  }

  Widget _buildColorCircle(Color color) {
    final currentColor = ref.watch(currentColorProvider);
    final isSelected = currentColor.value == color.value;

    return GestureDetector(
      onTap: () => ref.read(currentColorProvider.notifier).state = color,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: ScrapTheme.primaryText, width: 2.0)
              : Border.all(color: Colors.transparent),
        ),
      ),
    );
  }
}
