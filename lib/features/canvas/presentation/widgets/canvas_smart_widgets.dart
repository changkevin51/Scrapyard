import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Draggable table widget rendered over the canvas
// ─────────────────────────────────────────────────────────────────
class CanvasTableOverlay extends ConsumerWidget {
  final CanvasTable table;

  const CanvasTableOverlay({super.key, required this.table});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Positioned(
      left: table.position.dx,
      top: table.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          final tables = ref.read(canvasTablesProvider);
          final idx = tables.indexWhere((t) => t.id == table.id);
          if (idx == -1) return;
          final updated = tables[idx].copyWithPosition(
            tables[idx].position + d.delta,
          );
          final newList = List<CanvasTable>.from(tables);
          newList[idx] = updated;
          ref.read(canvasTablesProvider.notifier).state = newList;
        },
        child: Container(
          decoration: BoxDecoration(
            color: KotoTheme.cardSurface,
            border: Border.all(color: KotoTheme.dividers),
            borderRadius: BorderRadius.circular(4),
            boxShadow: KotoTheme.subtleShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Table header row with delete button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: KotoTheme.dividers,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${table.rows}×${table.cols} Table',
                      style: KotoTextStyles.caption.copyWith(
                        color: KotoTheme.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final tables = ref.read(canvasTablesProvider);
                        ref.read(canvasTablesProvider.notifier).state =
                            tables.where((t) => t.id != table.id).toList();
                      },
                      child: const Icon(Icons.close, size: 14,
                          color: KotoTheme.mutedText),
                    ),
                  ],
                ),
              ),
              // Cell grid
              for (int r = 0; r < table.rows; r++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int c = 0; c < table.cols; c++)
                      _TableCell(table: table, row: r, col: c),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableCell extends ConsumerWidget {
  final CanvasTable table;
  final int row, col;

  const _TableCell({required this.table, required this.row, required this.col});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: table.cellWidth,
      height: table.cellHeight,
      decoration: BoxDecoration(
        border: Border(
          right: col < table.cols - 1
              ? const BorderSide(color: KotoTheme.dividers)
              : BorderSide.none,
          bottom: row < table.rows - 1
              ? const BorderSide(color: KotoTheme.dividers)
              : BorderSide.none,
        ),
      ),
      child: TextField(
        controller: TextEditingController(text: table.cells[row][col]),
        onChanged: (val) {
          final tables = ref.read(canvasTablesProvider);
          final idx = tables.indexWhere((t) => t.id == table.id);
          if (idx == -1) return;
          final updated = tables[idx].copyWithCell(row, col, val);
          final newList = List<CanvasTable>.from(tables);
          newList[idx] = updated;
          ref.read(canvasTablesProvider.notifier).state = newList;
        },
        style: KotoTextStyles.body.copyWith(fontSize: 13),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Smart Action Bar — sits at the bottom-right of the canvas
// Provides: Insert Table | Convert OCR | Beautify Shapes
// ─────────────────────────────────────────────────────────────────
class CanvasSmartBar extends ConsumerStatefulWidget {
  final List<String> ocrTexts;
  final List<String> ocrStrokeIds; // stroke ids that produced the OCR text

  const CanvasSmartBar({
    super.key,
    required this.ocrTexts,
    required this.ocrStrokeIds,
  });

  @override
  ConsumerState<CanvasSmartBar> createState() => _CanvasSmartBarState();
}

class _CanvasSmartBarState extends ConsumerState<CanvasSmartBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  void _insertTable(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _InsertTableDialog(),
    );
  }

  void _convertOcr() {
    if (widget.ocrTexts.isEmpty) return;
    // Combine all OCR results into one text node centered on canvas
    final combined = widget.ocrTexts.join(' ');
    final node = CanvasTextItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: const Offset(80, 200),
      text: combined,
    );
    ref.read(canvasTextNodesProvider.notifier).update((s) => [...s, node]);
    // Hide source strokes
    ref.read(strokesProvider.notifier).hideStrokes(widget.ocrStrokeIds);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Converted to text node', style: KotoTextStyles.caption),
        backgroundColor: KotoTheme.accent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Action buttons (animated expand)
        SizeTransition(
          sizeFactor: _anim,
          axisAlignment: -1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SmartButton(
                label: 'Insert Table',
                icon: Icons.table_chart_outlined,
                onTap: () { _toggle(); _insertTable(context); },
              ),
              const SizedBox(height: 8),
              if (widget.ocrTexts.isNotEmpty)
                _SmartButton(
                  label: 'Convert Handwriting → Text',
                  icon: Icons.text_snippet_outlined,
                  onTap: () { _toggle(); _convertOcr(); },
                ),
              if (widget.ocrTexts.isNotEmpty) const SizedBox(height: 8),
            ],
          ),
        ),
        // Main FAB toggle
        GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _expanded ? KotoTheme.accent : KotoTheme.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: KotoTheme.dividers),
              boxShadow: KotoTheme.subtleShadow,
            ),
            child: Center(
              child: Text(
                '✦',
                style: KotoTextStyles.body.copyWith(
                  fontSize: 18,
                  color: _expanded ? Colors.white : KotoTheme.accent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SmartButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SmartButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: KotoTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: KotoTheme.dividers),
          boxShadow: KotoTheme.subtleShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: KotoTheme.accent),
            const SizedBox(width: 8),
            Text(label,
                style: KotoTextStyles.body.copyWith(
                    fontSize: 13, color: KotoTheme.primaryText)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Insert Table dialog
// ─────────────────────────────────────────────────────────────────
class _InsertTableDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends ConsumerState<_InsertTableDialog> {
  int _rows = 3;
  int _cols = 4;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KotoTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text('Insert Table',
          style: KotoTextStyles.heading.copyWith(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _counter('Rows', _rows, (v) => setState(() => _rows = v), 1, 12),
          const SizedBox(height: 16),
          _counter('Columns', _cols, (v) => setState(() => _cols = v), 1, 10),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText)),
        ),
        GestureDetector(
          onTap: () {
            final table = CanvasTable(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              position: const Offset(60, 120),
              rows: _rows,
              cols: _cols,
            );
            ref.read(canvasTablesProvider.notifier).update((s) => [...s, table]);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: KotoTheme.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Insert',
                style: KotoTextStyles.body.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _counter(
      String label, int value, void Function(int) onChange, int min, int max) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: KotoTextStyles.body),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            color: value > min ? KotoTheme.accent : KotoTheme.dividers,
            onPressed: value > min ? () => onChange(value - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: KotoTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            color: value < max ? KotoTheme.accent : KotoTheme.dividers,
            onPressed: value < max ? () => onChange(value + 1) : null,
          ),
        ]),
      ],
    );
  }
}
