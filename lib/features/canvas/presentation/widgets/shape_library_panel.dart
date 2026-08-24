import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Shape Library Panel
// Opens as a bottom sheet when the Shape tool icon is long-pressed.
// Shows pre-defined shapes + a "Draw your own" freehand option.
// ─────────────────────────────────────────────────────────────────
class ShapeLibraryPanel extends ConsumerWidget {
  const ShapeLibraryPanel({super.key});

  static const _shapes = <({ShapeType type, String label, String glyph})>[
    (type: ShapeType.none,      label: 'Draw',       glyph: '✏'),
    (type: ShapeType.circle,    label: 'Circle',     glyph: '○'),
    (type: ShapeType.oval,      label: 'Oval',       glyph: '⬭'),
    (type: ShapeType.square,    label: 'Square',     glyph: '□'),
    (type: ShapeType.rectangle, label: 'Rectangle',  glyph: '▭'),
    (type: ShapeType.triangle,  label: 'Triangle',   glyph: '△'),
    (type: ShapeType.diamond,   label: 'Diamond',    glyph: '◇'),
    (type: ShapeType.star,      label: 'Star',       glyph: '☆'),
    (type: ShapeType.line,      label: 'Line',       glyph: '─'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLibraryShapeProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(ScrapTheme.borderRadiusDefault)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: ScrapTheme.kraft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ScrapStampLabel(text: '⟨ Shapes ⟩'),
          const SizedBox(height: 8),
          Text('Shape Library', style: ScrapTextStyles.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text('Draw to snap  ·  pick Line for a ruler',
              style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _shapes.map((s) {
              final isActive = s.type == ShapeType.none
                  ? selected == null
                  : selected == s.type;
              return GestureDetector(
                onTap: () {
                  final next = s.type == ShapeType.none ? null : s.type;
                  ref.read(selectedLibraryShapeProvider.notifier).state = next;
                  // Ensure shape tool is active
                  ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.shape;
                  ref.read(isPenModeActiveProvider.notifier).state = true;
                  restoreToolThickness(ref, CanvasTool.shape);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 76,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive
                        ? ScrapTheme.accent.withValues(alpha: 0.12)
                        : ScrapTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? ScrapTheme.accent : ScrapTheme.dividers,
                      width: isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.glyph,
                        style: TextStyle(
                          fontSize: 28,
                          color: isActive ? ScrapTheme.accent : ScrapTheme.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.label,
                        style: ScrapTextStyles.caption.copyWith(
                          fontSize: 11,
                          color: isActive ? ScrapTheme.accent : ScrapTheme.mutedText,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (selected != null) ...[
            const Divider(color: ScrapTheme.dividers, height: 24),
            Row(
              children: [
                Text(
                  'Tap canvas to place selected shape',
                  style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.accent),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    ref.read(selectedLibraryShapeProvider.notifier).state = null;
                    Navigator.pop(context);
                  },
                  child: Text('Clear',
                      style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Show the shape library from a button tap
void showShapeLibrary(BuildContext context) {
  showScrapSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ShapeLibraryPanel(),
  );
}
