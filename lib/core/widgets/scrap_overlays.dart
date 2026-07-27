import 'package:flutter/material.dart';

import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';

/// Scrap-styled dialog with a short scale + slide entrance.
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
      return Stack(
        children: [
          Positioned.fill(
            // Visual-only scrim; real barrier still handles dismiss taps.
            child: IgnorePointer(
              child: ColoredBox(color: scrim),
            ),
          ),
          Center(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.02),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Scrap-styled modal bottom sheet with a snappier transition.
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
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: backgroundColor ?? ScrapTheme.cardSurface,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
    sheetAnimationStyle: AnimationStyle(
      duration: ScrapMotion.overlay,
      reverseDuration: ScrapMotion.overlay,
      curve: ScrapMotion.overlayCurve,
      reverseCurve: ScrapMotion.exitCurve,
    ),
    builder: builder,
  );
}
