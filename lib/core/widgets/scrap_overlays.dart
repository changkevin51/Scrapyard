import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';
import 'paper_surfaces.dart';
import 'torn_edge_clipper.dart';

/// Scrap-styled dialog with a short scale + slide + settle-rotation entrance.
Future<T?> showScrapDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: ScrapMotion.overlay,
    pageBuilder: (context, animation, secondaryAnimation) {
      return builder(context);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = animation.drive(
        CurveTween(
          curve: animation.status == AnimationStatus.reverse
              ? ScrapMotion.exitCurve
              : ScrapMotion.overlayCurve,
        ),
      );
      final scrim = Color.lerp(
        Colors.transparent,
        barrierColor ?? Colors.black.withValues(alpha: 0.45),
        curved.value,
      )!;
      final settle = Tween<double>(begin: 1.5 * math.pi / 180, end: 0).animate(
        curved,
      );
      final viewInsets = MediaQuery.viewInsetsOf(context);
      final safePadding = MediaQuery.paddingOf(context);
      final maxHeight = MediaQuery.sizeOf(context).height -
          viewInsets.bottom -
          safePadding.top -
          48;

      return Stack(
        children: [
          Positioned.fill(
            // Visual-only scrim; real barrier still handles dismiss taps.
            child: IgnorePointer(
              child: ColoredBox(color: scrim),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                  maxWidth: 560,
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.02),
                    end: Offset.zero,
                  ).animate(curved),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
                    child: AnimatedBuilder(
                      animation: settle,
                      builder: (context, child) => Transform.rotate(
                        angle: settle.value,
                        child: child,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Scrap-styled modal bottom sheet with a torn top edge.
///
/// Uses [sheetAnimationStyle] instead of a custom
/// [AnimationController] so barrier-tap and drag-to-dismiss keep working.
Future<T?> showScrapSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool tornTop = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: tornTop
        ? Colors.transparent
        : (backgroundColor ?? ScrapTheme.cardSurface),
    shape: tornTop
        ? null
        : (shape ??
            const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            )),
    sheetAnimationStyle: const AnimationStyle(
      duration: ScrapMotion.overlay,
      reverseDuration: ScrapMotion.overlay,
      curve: ScrapMotion.overlayCurve,
      reverseCurve: ScrapMotion.exitCurve,
    ),
    builder: (ctx) {
      final content = builder(ctx);
      if (!tornTop) return content;
      final sheetColor = backgroundColor ?? ScrapTheme.cardSurface;
      return Material(
        color: Colors.transparent,
        child: TornSheet(
          seed: 61,
          edges: const {TornEdge.top},
          amplitude: 5.0,
          color: sheetColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PaperGrabber(),
              content,
            ],
          ),
        ),
      );
    },
  );
}
