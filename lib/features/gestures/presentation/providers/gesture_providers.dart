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

final morseEnabledProvider = StateProvider<bool>((ref) => true);
final edgeSwipesEnabledProvider = StateProvider<bool>((ref) => true);
final tapHoldExpandEnabledProvider = StateProvider<bool>((ref) => true);
final multiFingerEnabledProvider = StateProvider<bool>((ref) => true);

final morseMappingsProvider = StateProvider<Map<MorsePattern, GestureAction>>((ref) {
  return {
    const MorsePattern([MorseSymbol.dot, MorseSymbol.dot]): GestureAction.contextualPopupOnLastWord,
    const MorsePattern([MorseSymbol.dot, MorseSymbol.dash]): GestureAction.toggleLanguageSidebar,
    const MorsePattern([MorseSymbol.dash, MorseSymbol.dot]): GestureAction.summarizeDocument,
    const MorsePattern([MorseSymbol.dash, MorseSymbol.dash]): GestureAction.openAiPanel,
  };
});
