import 'package:flutter/services.dart';

/// Central haptic wrappers — easy to tune or disable in one place.
class ScrapFeedback {
  ScrapFeedback._();

  /// Tool / chip / sidebar selection.
  static void tap() => HapticFeedback.selectionClick();

  /// Meaningful actions: folder open, send, Smelt trigger.
  static void action() => HapticFeedback.lightImpact();

  /// Destructive confirms: delete, clear data.
  static void warn() => HapticFeedback.mediumImpact();
}
