import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/gesture_action.dart';

class GestureActionNotifier extends StateNotifier<GestureAction> {
  GestureActionNotifier() : super(GestureAction.none);

  void dispatch(GestureAction action) {
    state = action;
    // Reset after microtask guarantees listeners can react
    Future.microtask(() => state = GestureAction.none);
  }
}

final gestureActionProvider = StateNotifierProvider<GestureActionNotifier, GestureAction>((ref) {
  return GestureActionNotifier();
});

final edgeSwipesEnabledProvider = StateProvider<bool>((ref) => true);
final tapHoldExpandEnabledProvider = StateProvider<bool>((ref) => true);
final multiFingerEnabledProvider = StateProvider<bool>((ref) => true);

/// Two-finger tap on the canvas undoes the last stroke change.
final twoFingerTapUndoEnabledProvider = StateProvider<bool>((ref) => true);

/// Three-finger tap on the canvas redoes the last undone change.
final threeFingerTapRedoEnabledProvider = StateProvider<bool>((ref) => true);

/// Holding the S Pen / stylus side button temporarily switches to eraser.
final sPenButtonEraserEnabledProvider = StateProvider<bool>((ref) => true);
