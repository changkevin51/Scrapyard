import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
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
            color: ScrapTheme.cardSurface,
            border: Border.all(color: ScrapTheme.dividers),
            borderRadius: BorderRadius.circular(4),
            boxShadow: ScrapTheme.subtleShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: ScrapTheme.dividers,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${table.rows}×${table.cols} Table',
                      style: ScrapTextStyles.caption.copyWith(
                        color: ScrapTheme.secondaryText,
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
                      child: const Icon(Icons.close,
                          size: 14, color: ScrapTheme.mutedText),
                    ),
                  ],
                ),
              ),
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
              ? const BorderSide(color: ScrapTheme.dividers)
              : BorderSide.none,
          bottom: row < table.rows - 1
              ? const BorderSide(color: ScrapTheme.dividers)
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
        style: ScrapTextStyles.body.copyWith(fontSize: 13),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
      ),
    );
  }
}

/// Convert OCR text results into a canvas text node and hide source strokes.
void convertOcrToTextNode(
  WidgetRef ref,
  BuildContext context, {
  required List<String> ocrTexts,
  required List<String> ocrStrokeIds,
}) {
  if (ocrTexts.isEmpty) return;
  final combined = ocrTexts.join(' ');
  final node = CanvasTextItem(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    position: const Offset(80, 200),
    text: combined,
  );
  ref.read(canvasTextNodesProvider.notifier).add(node);
  ref.read(strokesProvider.notifier).hideStrokes(ocrStrokeIds);
  showPaperToast(context, 'Converted to text node');
}

Future<void> showInsertTableDialog(BuildContext context) {
  return showScrapDialog(
    context: context,
    builder: (_) => const InsertTableDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────
// AI Chat FAB — bottom-right, opens the Ask panel
// ─────────────────────────────────────────────────────────────────
class CanvasSmartBar extends ConsumerWidget {
  const CanvasSmartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(chatPanelOpenProvider);
    return GestureDetector(
      onTap: () {
        ref.read(chatPanelOpenProvider.notifier).state = !open;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: open ? ScrapTheme.accent : ScrapTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ScrapTheme.dividers),
          boxShadow: ScrapTheme.subtleShadow,
        ),
        child: Center(
          child: Text(
            '✦',
            style: ScrapTextStyles.body.copyWith(
              fontSize: 18,
              color: open ? Colors.white : ScrapTheme.accent,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Insert Table dialog
// ─────────────────────────────────────────────────────────────────
class InsertTableDialog extends ConsumerStatefulWidget {
  const InsertTableDialog({super.key});

  @override
  ConsumerState<InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends ConsumerState<InsertTableDialog> {
  int _rows = 3;
  int _cols = 4;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ScrapTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text('Insert Table',
          style: ScrapTextStyles.heading.copyWith(fontSize: 18)),
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
              style:
                  ScrapTextStyles.body.copyWith(color: ScrapTheme.mutedText)),
        ),
        GestureDetector(
          onTap: () {
            final table = CanvasTable(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              position: const Offset(60, 120),
              rows: _rows,
              cols: _cols,
            );
            ref
                .read(canvasTablesProvider.notifier)
                .update((s) => [...s, table]);
            Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: ScrapTheme.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Insert',
                style: ScrapTextStyles.body.copyWith(
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
        Text(label, style: ScrapTextStyles.body),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            color: value > min ? ScrapTheme.accent : ScrapTheme.dividers,
            onPressed: value > min ? () => onChange(value - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: ScrapTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            color: value < max ? ScrapTheme.accent : ScrapTheme.dividers,
            onPressed: value < max ? () => onChange(value + 1) : null,
          ),
        ]),
      ],
    );
  }
}
