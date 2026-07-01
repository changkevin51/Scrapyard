import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Text Sticker — transparent floating text annotation.
// No background. Moves, resizes, deletes.
// ─────────────────────────────────────────────────────────────────
class CanvasTextSticker extends ConsumerStatefulWidget {
  final CanvasTextItem item;

  const CanvasTextSticker({super.key, required this.item});

  @override
  ConsumerState<CanvasTextSticker> createState() => _CanvasTextStickerState();
}

class _CanvasTextStickerState extends ConsumerState<CanvasTextSticker> {
  bool _editing  = false;
  bool _selected = false;
  double _fontSize = 18.0;
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl  = TextEditingController(text: widget.item.text);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _updatePos(Offset delta) {
    _mutate((items, idx) =>
        items[idx].copyWith(position: items[idx].position + delta));
  }

  void _saveText(String text) {
    _mutate((items, idx) => items[idx].copyWith(text: text));
  }

  void _delete() {
    ref.read(canvasTextNodesProvider.notifier)
        .update((s) => s.where((i) => i.id != widget.item.id).toList());
  }

  void _mutate(CanvasTextItem Function(List<CanvasTextItem>, int) fn) {
    final items = ref.read(canvasTextNodesProvider);
    final idx   = items.indexWhere((i) => i.id == widget.item.id);
    if (idx < 0) return;
    final newList = List<CanvasTextItem>.from(items);
    newList[idx] = fn(newList, idx);
    ref.read(canvasTextNodesProvider.notifier).state = newList;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.item.position.dx,
      top:  widget.item.position.dy,
      child: GestureDetector(
        onTap: () {
          setState(() { _selected = true; _editing = true; });
          _focus.requestFocus();
        },
        onPanUpdate: (d) {
          if (!_editing) _updatePos(d.delta);
        },
        onPanEnd: (_) {},
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Transparent text body ──────────────────────────
            Container(
              constraints: const BoxConstraints(minWidth: 40, maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: _selected ? BoxDecoration(
                border: Border.all(
                  color: KotoTheme.accent.withValues(alpha: 0.4),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ) : null,
              child: _editing
                  ? IntrinsicWidth(
                      child: TextField(
                        controller: _ctrl,
                        focusNode:  _focus,
                        maxLines: null,
                        style: TextStyle(
                          fontSize: _fontSize,
                          color: KotoTheme.primaryText,
                          decoration: TextDecoration.none,
                          fontFamily: 'Noto Serif',
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (t) => _saveText(t),
                        onSubmitted: (_) {
                          setState(() { _editing = false; _selected = false; });
                          _focus.unfocus();
                        },
                      ),
                    )
                  : Text(
                      _ctrl.text.isEmpty ? '…' : _ctrl.text,
                      style: TextStyle(
                        fontSize: _fontSize,
                        color: _ctrl.text.isEmpty
                            ? KotoTheme.mutedText
                            : KotoTheme.primaryText,
                        decoration: TextDecoration.none,
                        fontFamily: 'Noto Serif',
                      ),
                    ),
            ),

            // ── Controls (only when selected) ─────────────────
            if (_selected) ...[
              // Done editing
              if (_editing)
                Positioned(
                  top: -18, left: 0,
                  child: GestureDetector(
                    onTap: () {
                      _saveText(_ctrl.text);
                      setState(() { _editing = false; _selected = false; });
                      _focus.unfocus();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KotoTheme.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Done',
                          style: KotoTextStyles.caption.copyWith(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ),
                ),

              // Delete
              Positioned(
                top: -14, right: -14,
                child: GestureDetector(
                  onTap: _delete,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: KotoTheme.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: KotoTheme.dividers),
                      boxShadow: KotoTheme.subtleShadow,
                    ),
                    child: const Icon(Icons.close, size: 12,
                        color: KotoTheme.secondaryText),
                  ),
                ),
              ),

              // Font size − (bottom left)
              Positioned(
                bottom: -16, left: 0,
                child: GestureDetector(
                  onTap: () => setState(
                      () => _fontSize = (_fontSize - 2).clamp(10.0, 80.0)),
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: KotoTheme.cardSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: KotoTheme.dividers),
                    ),
                    child: const Icon(Icons.remove, size: 12,
                        color: KotoTheme.secondaryText),
                  ),
                ),
              ),

              // Font size + (bottom right)
              Positioned(
                bottom: -16, right: -14,
                child: GestureDetector(
                  onTap: () => setState(
                      () => _fontSize = (_fontSize + 2).clamp(10.0, 80.0)),
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: KotoTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
