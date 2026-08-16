import 'package:flutter/material.dart';

/// Shared durations and curves for scrap-paper motion.
class ScrapMotion {
  ScrapMotion._();

  static const Duration press = Duration(milliseconds: 140);
  static const Duration fast = Duration(milliseconds: 90);
  static const Duration panel = Duration(milliseconds: 250);
  static const Duration overlay = Duration(milliseconds: 200);
  static const Duration cardEnter = Duration(milliseconds: 320);
  static const Duration route = Duration(milliseconds: 280);
  /// Long-press before a desk card lifts — long enough to keep scrolling.
  static const Duration dragHold = Duration(milliseconds: 450);

  static const Curve pressCurve = Curves.easeOutBack;
  static const Curve panelCurve = Curves.easeOutCubic;
  static const Curve overlayCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve cardEnterCurve = Curves.easeOutCubic;
  static const Curve routeCurve = Curves.easeOutCubic;
}
