import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/gesture_action.dart';

class GestureActionNotifier extends StateNotifier<GestureAction> {
  GestureActionNotifier() : super(GestureAction.none);

  void dispatch(GestureAction action) {
    state = action;
    Future.microtask(() => state = GestureAction.none);
  }
}

final gestureActionProvider =
    StateNotifierProvider<GestureActionNotifier, GestureAction>((ref) {
  return GestureActionNotifier();
});

final edgeSwipesEnabledProvider = StateProvider<bool>((ref) => true);
final tapHoldExpandEnabledProvider = StateProvider<bool>((ref) => true);
final multiFingerEnabledProvider = StateProvider<bool>((ref) => true);

class _BoolPrefNotifier extends StateNotifier<bool> {
  _BoolPrefNotifier(this._key, this._defaultValue) : super(_defaultValue) {
    _load();
  }

  final String _key;
  final bool _defaultValue;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getBool(_key) ?? _defaultValue;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final twoFingerTapUndoEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier('gesture_two_finger_undo', true);
});

final threeFingerTapRedoEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier('gesture_three_finger_redo', true);
});

final sPenButtonEraserEnabledProvider =
    StateNotifierProvider<_BoolPrefNotifier, bool>((ref) {
  return _BoolPrefNotifier('gesture_spen_eraser', true);
});
