import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../ai_engine/presentation/widgets/latex_markdown_view.dart';
import '../providers/canvas_providers.dart';

/// Kraft slip taped beside a problem — persisted Smelt result on the page.
class TapedSlipOverlay extends ConsumerStatefulWidget {
  final CanvasTextItem item;

  const TapedSlipOverlay({super.key, required this.item});

  @override
  ConsumerState<TapedSlipOverlay> createState() => _TapedSlipOverlayState();
}

class _TapedSlipOverlayState extends ConsumerState<TapedSlipOverlay> {
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);

  int? _dragPointer;
  Offset? _lastGlobal;
  int? _ignorePointer;

  void _claimPointer(int pointer) {
    ref.read(tapedSlipActivePointerProvider.notifier).state = pointer;
  }

  void _releasePointer(int pointer) {
    final notifier = ref.read(tapedSlipActivePointerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (notifier.state == pointer) notifier.state = null;
    });
  }

  void _bindPointer(int pointer) {
    GestureBinding.instance.pointerRouter.addRoute(pointer, _onRoutedPointer);
  }

  void _unbindPointer(int pointer) {
    GestureBinding.instance.pointerRouter.removeRoute(pointer, _onRoutedPointer);
  }

  void _onRoutedPointer(PointerEvent e) {
    if (e is PointerMoveEvent) {
      _onMove(e);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _onEnd(e);
    }
  }

  void _onDown(PointerDownEvent e) {
    if (_ignorePointer == e.pointer) return;
    if (_dragPointer != null) {
      _unbindPointer(_dragPointer!);
    }
    _dragPointer = e.pointer;
    _lastGlobal = e.position;
    _claimPointer(e.pointer);
    _bindPointer(e.pointer);
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _dragPointer || _lastGlobal == null) return;
    final delta = _globalDeltaToWorld(e.position, _lastGlobal!);
    _lastGlobal = e.position;
    if (delta == Offset.zero) return;
    // Visual-only: avoid rewriting note state / re-parsing LaTeX every frame.
    _drag.value += delta;
  }

  void _onEnd(PointerEvent e) {
    if (e.pointer != _dragPointer && e.pointer != _ignorePointer) return;
    if (e.pointer == _dragPointer) {
      _unbindPointer(e.pointer);
      _releasePointer(e.pointer);
      _dragPointer = null;
      _lastGlobal = null;
      final delta = _drag.value;
      if (delta != Offset.zero) {
        ref.read(canvasTextNodesProvider.notifier).upsert(
              widget.item.copyWith(position: widget.item.position + delta),
            );
      }
    }
    if (e.pointer == _ignorePointer) {
      _releasePointer(e.pointer);
      _ignorePointer = null;
    }
  }

  /// Map a global pointer step into the stack/world space the slip lives in.
  Offset _globalDeltaToWorld(Offset global, Offset lastGlobal) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return global - lastGlobal;
    RenderObject? parent = box.parent;
    while (parent != null && parent is! RenderBox) {
      parent = parent.parent;
    }
    if (parent is! RenderBox) return global - lastGlobal;
    return parent.globalToLocal(global) - parent.globalToLocal(lastGlobal);
  }

  void _delete(int pointer) {
    if (_dragPointer != null) {
      _unbindPointer(_dragPointer!);
      _dragPointer = null;
      _lastGlobal = null;
    }
    _drag.value = Offset.zero;
    _ignorePointer = pointer;
    _claimPointer(pointer);
    _releasePointer(pointer);
    ref.read(canvasTextNodesProvider.notifier).deleteIds([widget.item.id]);
  }

  @override
  void didUpdateWidget(covariant TapedSlipOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.position != widget.item.position) {
      _drag.value = Offset.zero;
    }
  }

  @override
  void dispose() {
    final pointer = _dragPointer;
    if (pointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, _onRoutedPointer);
    }
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final steps = item.tapedSteps?.trim();
    final body = RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        child: Transform.rotate(
          angle: -1.2 * math.pi / 180,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  decoration: BoxDecoration(
                    color: ScrapTheme.cardSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: ScrapTheme.kraft.withValues(alpha: 0.85),
                    ),
                    boxShadow: ScrapTheme.deskShadow,
                  ),
                  child: IgnorePointer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '⟨ taped ⟩',
                          style: ScrapTextStyles.stamp.copyWith(
                            fontSize: 9,
                            color: ScrapTheme.mutedText,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (item.text.trim().isNotEmpty)
                          LatexMarkdownView(
                            text: item.text,
                            compact: true,
                            baseStyle: ScrapTextStyles.body.copyWith(
                              fontSize: 16,
                              color: ScrapTheme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (steps != null && steps.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          LatexMarkdownView(
                            text: steps,
                            compact: true,
                            baseStyle: ScrapTextStyles.body.copyWith(
                              fontSize: 13,
                              color: ScrapTheme.bodyText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: -7,
                  left: 22,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Container(
                      width: 52,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ScrapTheme.tape.withValues(alpha: 0.92),
                        border: Border.all(
                          color: ScrapTheme.kraft.withValues(alpha: 0.6),
                          width: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Semantics(
                    button: true,
                    label: 'Delete taped slip',
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _delete(e.pointer),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: ScrapTheme.mutedText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _drag,
        child: body,
        builder: (context, delta, child) {
          return Transform.translate(
            offset: delta,
            filterQuality: FilterQuality.low,
            child: child,
          );
        },
      ),
    );
  }
}
