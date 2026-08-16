import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../providers/canvas_viewport_provider.dart';
import 'handwriting_canvas.dart';

/// Screen-sized infinite canvas surface.
///
/// Ink is painted by [HandwritingCanvas] in screen space (painters apply the
/// world matrix + cull). [worldOverlays] sit under a [Transform] so widgets
/// that use world-coordinate [Positioned] layouts keep working.
/// [screenOverlays] are drawn in screen space (selection UI after converting
/// world rects, FABs, etc.).
class InfiniteCanvasSurface extends ConsumerWidget {
  /// World-coordinate overlays (text, tables).
  final List<Widget> worldOverlays;

  /// Screen-coordinate overlays (selection UI, hints).
  final List<Widget> screenOverlays;

  final GlobalKey? inkRepaintKey;

  final void Function(PointerDownEvent)? onPointerDown;
  final void Function(PointerMoveEvent)? onPointerMove;
  final void Function(PointerUpEvent)? onPointerUp;
  final void Function(PointerCancelEvent)? onPointerCancel;

  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  final bool suppressTouchScroll;

  const InfiniteCanvasSurface({
    super.key,
    this.worldOverlays = const [],
    this.screenOverlays = const [],
    this.inkRepaintKey,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onTapDown,
    this.onTapUp,
    this.onLongPressStart,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.suppressTouchScroll = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewport = ref.watch(canvasViewportProvider);
    final zoom = viewport.scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(canvasViewportProvider.notifier).setViewportSize(size);
          }
        });

        return ColoredBox(
          color: ScrapTheme.codeSurface,
          child: Listener(
            onPointerDown: onPointerDown,
            onPointerMove: onPointerMove,
            onPointerUp: onPointerUp,
            onPointerCancel: onPointerCancel,
            child: GestureDetector(
              onTapDown: onTapDown,
              onTapUp: onTapUp,
              onLongPressStart: onLongPressStart,
              onPanStart: onPanStart,
              onPanUpdate: onPanUpdate,
              onPanEnd: onPanEnd,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  RepaintBoundary(
                    key: inkRepaintKey,
                    child: HandwritingCanvas(
                      infiniteMode: true,
                      zoomLevel: zoom,
                      onZoomChanged: (_) {},
                      suppressTouchScroll: suppressTouchScroll,
                    ),
                  ),
                  if (zoom >= 0.15)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: PaperGrain(opacity: 0.022),
                        ),
                      ),
                    ),
                  // World-space widget overlays (text/tables).
                  Transform(
                    transform: viewport.matrix,
                    alignment: Alignment.topLeft,
                    filterQuality: FilterQuality.low,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: worldOverlays,
                      ),
                    ),
                  ),
                  ...screenOverlays,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
