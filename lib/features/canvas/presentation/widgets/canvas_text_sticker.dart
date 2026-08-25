import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../providers/canvas_providers.dart';

// ─────────────────────────────────────────────────────────────────
// Text Sticker — transparent floating text annotation.
// Draggable / resizable while selected; empty nodes prune on deselect.
// Uses Listener so stylus and touch both drive move/resize.
// ─────────────────────────────────────────────────────────────────
class CanvasTextSticker extends ConsumerStatefulWidget {
  final CanvasTextItem item;

  const CanvasTextSticker({super.key, required this.item});

  @override
  ConsumerState<CanvasTextSticker> createState() => _CanvasTextStickerState();
}

class _CanvasTextStickerState extends ConsumerState<CanvasTextSticker>
    with WidgetsBindingObserver {
  bool _editing = false;
  bool _selected = false;
  bool _finishing = false;
  late double _fontSize;
  late TextEditingController _ctrl;
  late FocusNode _focus;

  int? _movePointer;
  int? _resizePointer;
  int _revealGen = 0;

  /// Padding reserved for grip / resize so they stay inside hit bounds.
  static const double _chrome = 20.0;
  static const double _handleSize = 28.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fontSize = widget.item.fontSize;
    _ctrl = TextEditingController(text: widget.item.text);
    _ctrl.addListener(_onCtrlChanged);
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(activeTextNodeIdProvider) == widget.item.id) {
        _enterEdit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CanvasTextSticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.fontSize != widget.item.fontSize &&
        widget.item.fontSize != _fontSize) {
      _fontSize = widget.item.fontSize;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_onCtrlChanged);
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (_focus.hasFocus || _editing) {
      _ensureVisibleAboveKeyboard();
    }
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _ensureVisibleAboveKeyboard();
      return;
    }
    if (!_editing) return;
    _finishEditing();
  }

  /// Publish this sticker's screen rect and ask the note editor to scroll/pan.
  void _ensureVisibleAboveKeyboard() {
    final gen = ++_revealGen;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || gen != _revealGen) return;
      if (!_focus.hasFocus && !_editing) return;

      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      final prev = ref.read(activeTextGlobalRectProvider);
      if (prev != null &&
          (prev.top - rect.top).abs() < 1.5 &&
          (prev.bottom - rect.bottom).abs() < 1.5 &&
          (prev.left - rect.left).abs() < 1.5) {
        return;
      }
      ref.read(activeTextGlobalRectProvider.notifier).state = rect;
    });
  }

  TextStyle get _textStyle => TextStyle(
        fontSize: _fontSize,
        color: ScrapTheme.primaryText,
        decoration: TextDecoration.none,
        fontFamily: 'Noto Serif',
      );

  static const double _hPad = 4.0;

  /// Widest line of text (no padding). Used so the editor never soft-wraps
  /// while typing — only explicit newlines create new lines.
  double _textWidth() {
    final raw = _ctrl.text.isEmpty ? 'Type…' : _ctrl.text;
    final style = _textStyle;
    double widest = 48;
    for (final line in raw.split('\n')) {
      final painter = TextPainter(
        text: TextSpan(text: line.isEmpty ? ' ' : line, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
    }
    // Caret + next glyph headroom so a new character never exceeds the box
    // for a frame and triggers a soft line break.
    return widest + math.max(32.0, _fontSize * 1.5);
  }

  void _enterEdit() {
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
      return;
    }
    setState(() {
      _selected = true;
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _ensureVisibleAboveKeyboard();
      }
    });
  }

  void _finishEditing({bool consumeNextCanvasTap = false}) {
    if (_finishing || !_editing) return;
    _finishing = true;

    final text = _ctrl.text;
    final wasActive = ref.read(activeTextNodeIdProvider) == widget.item.id;

    if (consumeNextCanvasTap) {
      // Prevent the same outside-tap from immediately creating a new box.
      ref.read(consumeTextCanvasTapProvider.notifier).state = true;
    }

    if (text.trim().isEmpty) {
      ref.read(canvasTextNodesProvider.notifier).deleteIds([widget.item.id]);
    } else {
      _saveText(text);
      if (mounted) {
        setState(() {
          _editing = false;
          _selected = false;
        });
      }
    }

    if (wasActive) {
      ref.read(activeTextNodeIdProvider.notifier).state = null;
    }

    if (_focus.hasFocus) {
      _focus.unfocus();
    }
    _finishing = false;
  }

  void _ensureSelected() {
    if (ref.read(activeTextNodeIdProvider) != widget.item.id) {
      ref.read(activeTextNodeIdProvider.notifier).state = widget.item.id;
    }
  }

  void _updatePos(Offset delta) {
    if (delta == Offset.zero) return;
    _mutate((items, idx) =>
        items[idx].copyWith(position: items[idx].position + delta));
  }

  void _updateFontSize(double size) {
    final clamped = size.clamp(10.0, 80.0);
    if ((clamped - _fontSize).abs() < 0.01) return;
    setState(() => _fontSize = clamped);
    _mutate((items, idx) => items[idx].copyWith(fontSize: clamped));
  }

  void _saveText(String text) {
    _mutate((items, idx) => items[idx].copyWith(text: text));
  }

  void _delete() {
    // Prevent focus-loss / onTapOutside from racing and deselecting first.
    _finishing = true;
    _editing = false;
    _selected = false;
    if (_focus.hasFocus) {
      _focus.unfocus();
    }
    if (ref.read(activeTextNodeIdProvider) == widget.item.id) {
      ref.read(activeTextNodeIdProvider.notifier).state = null;
    }
    ref.read(canvasTextNodesProvider.notifier).deleteIds([widget.item.id]);
  }

  void _mutate(CanvasTextItem Function(List<CanvasTextItem>, int) fn) {
    final items = ref.read(canvasTextNodesProvider);
    final idx = items.indexWhere((i) => i.id == widget.item.id);
    if (idx < 0) return;
    final newList = List<CanvasTextItem>.from(items);
    newList[idx] = fn(newList, idx);
    ref.read(canvasTextNodesProvider.notifier).upsert(newList[idx]);
  }

  void _onMoveDown(PointerDownEvent e) {
    _ensureSelected();
    _movePointer = e.pointer;
  }

  void _onMoveMove(PointerMoveEvent e) {
    if (e.pointer != _movePointer) return;
    _updatePos(e.localDelta);
  }

  void _onMoveEnd(PointerEvent e) {
    if (e.pointer != _movePointer) return;
    _movePointer = null;
  }

  void _onResizeDown(PointerDownEvent e) {
    _ensureSelected();
    _resizePointer = e.pointer;
  }

  void _onResizeMove(PointerMoveEvent e) {
    if (e.pointer != _resizePointer) return;
    final step = (e.localDelta.dx + e.localDelta.dy) * 0.4;
    if (step.abs() >= 0.05) _updateFontSize(_fontSize + step);
  }

  void _onResizeEnd(PointerEvent e) {
    if (e.pointer != _resizePointer) return;
    _resizePointer = null;
  }

  Widget _pointerSurface({
    required void Function(PointerDownEvent) onDown,
    required void Function(PointerMoveEvent) onMove,
    required void Function(PointerEvent) onEnd,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: onDown,
      onPointerMove: onMove,
      onPointerUp: onEnd,
      onPointerCancel: onEnd,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(activeTextNodeIdProvider, (prev, next) {
      if (next == widget.item.id) {
        _enterEdit();
      } else if (_editing && prev == widget.item.id) {
        if (_focus.hasFocus) {
          _focus.unfocus();
        } else {
          _finishEditing();
        }
      }
    });

    final chrome = _selected ? _chrome : 0.0;
    final textWidth = _textWidth();
    final tool = ref.watch(activeCanvasToolProvider);
    final passThroughSelection =
        tool == CanvasTool.smelt || tool == CanvasTool.lasso;

    return Positioned(
      left: widget.item.position.dx - chrome,
      top: widget.item.position.dy - chrome,
      child: IgnorePointer(
        ignoring: passThroughSelection,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _ensureSelected,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                chrome,
                chrome,
                chrome,
                _selected ? _handleSize : chrome,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: _hPad, vertical: 2),
                decoration: _selected
                    ? BoxDecoration(
                        border: Border.all(
                          color: ScrapTheme.accent.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: SizedBox(
                  width: textWidth,
                  child: _editing
                      ? TextField(
                          controller: _ctrl,
                          focusNode: _focus,
                          autofocus: true,
                          maxLines: null,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: _textStyle,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Type…',
                            hintStyle: TextStyle(
                              color: ScrapTheme.mutedText,
                              fontFamily: 'Noto Serif',
                            ),
                          ),
                          onChanged: (t) => _saveText(t),
                          onTapOutside: (_) =>
                              _finishEditing(consumeNextCanvasTap: true),
                        )
                      : Text(
                          _ctrl.text.isEmpty ? '…' : _ctrl.text,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: _fontSize,
                            color: _ctrl.text.isEmpty
                                ? ScrapTheme.mutedText
                                : ScrapTheme.primaryText,
                            decoration: TextDecoration.none,
                            fontFamily: 'Noto Serif',
                          ),
                        ),
                ),
              ),
            ),

            if (_selected) ...[
              Positioned(
                top: 0,
                left: 0,
                right: _handleSize,
                height: _chrome,
                child: TextFieldTapRegion(
                  child: _pointerSurface(
                    onDown: _onMoveDown,
                    onMove: _onMoveMove,
                    onEnd: _onMoveEnd,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: ScrapTheme.accent.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Delete — top right (Listener so stylus + touch both work)
              Positioned(
                top: 0,
                right: 0,
                child: TextFieldTapRegion(
                  child: Semantics(
                    button: true,
                    label: 'Delete text',
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => _delete(),
                      child: Container(
                        width: _handleSize,
                        height: _handleSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ScrapTheme.cardSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: ScrapTheme.dividers),
                          boxShadow: ScrapTheme.subtleShadow,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: ScrapTheme.secondaryText),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: _chrome,
                bottom: _handleSize,
                width: _chrome,
                child: TextFieldTapRegion(
                  child: _pointerSurface(
                    onDown: _onMoveDown,
                    onMove: _onMoveMove,
                    onEnd: _onMoveEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: _chrome,
                bottom: _handleSize,
                width: _chrome,
                child: TextFieldTapRegion(
                  child: _pointerSurface(
                    onDown: _onMoveDown,
                    onMove: _onMoveMove,
                    onEnd: _onMoveEnd,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: TextFieldTapRegion(
                  child: _pointerSurface(
                    onDown: _onResizeDown,
                    onMove: _onResizeMove,
                    onEnd: _onResizeEnd,
                    child: Container(
                      width: _handleSize,
                      height: _handleSize,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: ScrapTheme.accent,
                        shape: BoxShape.circle,
                        boxShadow: ScrapTheme.subtleShadow,
                      ),
                      child: const Icon(Icons.open_in_full,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
