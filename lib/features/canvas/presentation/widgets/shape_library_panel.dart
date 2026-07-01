import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
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
        color: KotoTheme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: KotoTheme.dividers,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Shape Library', style: KotoTextStyles.heading.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text('Tap to place  ·  or draw your own',
              style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
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
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 76,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive
                        ? KotoTheme.accent.withValues(alpha: 0.12)
                        : KotoTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? KotoTheme.accent : KotoTheme.dividers,
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
                          color: isActive ? KotoTheme.accent : KotoTheme.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.label,
                        style: KotoTextStyles.caption.copyWith(
                          fontSize: 11,
                          color: isActive ? KotoTheme.accent : KotoTheme.mutedText,
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
            const Divider(color: KotoTheme.dividers, height: 24),
            Row(
              children: [
                Text(
                  'Tap canvas to place selected shape',
                  style: KotoTextStyles.caption.copyWith(color: KotoTheme.accent),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    ref.read(selectedLibraryShapeProvider.notifier).state = null;
                    Navigator.pop(context);
                  },
                  child: Text('Clear',
                      style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
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
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ShapeLibraryPanel(),
  );
}
