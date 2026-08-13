import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ai_engine/domain/models/smelt_response.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../domain/smelt_guide_step.dart';

const smeltGuideCompletedPrefsKey = 'smelt_guide_completed';
const smeltToolHintSeenPrefsKey = 'smelt_tool_hint_seen';

class SmeltGuideState {
  final SmeltGuideStep step;
  final bool paused;
  final bool hasInk;
  final bool hasSelection;
  final bool isSmelting;
  final bool smeltFailed;
  final bool stepsRevealed;

  const SmeltGuideState({
    this.step = SmeltGuideStep.idle,
    this.paused = false,
    this.hasInk = false,
    this.hasSelection = false,
    this.isSmelting = false,
    this.smeltFailed = false,
    this.stepsRevealed = false,
  });

  bool get isActive => step.isActive && !paused;

  /// Keep the Smelt result card open while the tour is using it.
  bool get locksSmeltPopup =>
      isActive &&
      (step == SmeltGuideStep.chooseSmelt ||
          step == SmeltGuideStep.showSteps ||
          step == SmeltGuideStep.askNext);

  String? get actionLabel => switch (step) {
        SmeltGuideStep.writeProblem => hasInk ? 'Next' : null,
        SmeltGuideStep.selectExpression => hasSelection ? 'Next' : null,
        SmeltGuideStep.showSteps => stepsRevealed ? 'Next' : null,
        SmeltGuideStep.chatSelect => 'Got it',
        SmeltGuideStep.enjoy => "Let's go",
        _ => null,
      };

  SmeltGuideState copyWith({
    SmeltGuideStep? step,
    bool? paused,
    bool? hasInk,
    bool? hasSelection,
    bool? isSmelting,
    bool? smeltFailed,
    bool? stepsRevealed,
  }) {
    return SmeltGuideState(
      step: step ?? this.step,
      paused: paused ?? this.paused,
      hasInk: hasInk ?? this.hasInk,
      hasSelection: hasSelection ?? this.hasSelection,
      isSmelting: isSmelting ?? this.isSmelting,
      smeltFailed: smeltFailed ?? this.smeltFailed,
      stepsRevealed: stepsRevealed ?? this.stepsRevealed,
    );
  }
}

class SmeltGuideNotifier extends StateNotifier<SmeltGuideState> {
  SmeltGuideNotifier() : super(const SmeltGuideState());

  Future<bool> _isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(smeltGuideCompletedPrefsKey) == true;
  }

  Future<void> _persistCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(smeltGuideCompletedPrefsKey, true);
    await prefs.setBool(smeltToolHintSeenPrefsKey, true);
  }

  Future<void> _clearCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(smeltGuideCompletedPrefsKey, false);
  }

  /// First-run after an API key save. No-op if the tour was already finished.
  /// [force] (debug replay) always resets to the Home spotlight immediately.
  Future<void> startFromHome({bool force = false}) async {
    if (!force && await _isCompleted()) return;
    if (!mounted) return;
    state = const SmeltGuideState(step: SmeltGuideStep.openScrap);
    if (force) await _clearCompleted();
  }

  void notifyOpenedScrap() {
    if (state.step == SmeltGuideStep.openScrap) {
      state = const SmeltGuideState(step: SmeltGuideStep.writeProblem);
      return;
    }
    if (state.paused && state.step.isEditorStep) {
      state = state.copyWith(paused: false);
    }
  }

  void pause() {
    if (!state.step.isEditorStep) return;
    if (state.paused) return;
    state = state.copyWith(paused: true);
  }

  void resume() {
    if (!state.paused) return;
    state = state.copyWith(paused: false);
  }

  void markInk() {
    if (state.step != SmeltGuideStep.writeProblem) return;
    if (state.hasInk) return;
    state = state.copyWith(hasInk: true);
  }

  void onSmeltToolSelected() {
    if (!state.isActive) return;
    if (state.step == SmeltGuideStep.tapSmelt) {
      _go(SmeltGuideStep.selectExpression);
    }
  }

  void onSelectionReady() {
    if (!state.isActive) return;
    if (state.step != SmeltGuideStep.selectExpression) return;
    if (state.hasSelection) return;
    state = state.copyWith(hasSelection: true);
  }

  /// User tapped ⟨ Smelt ⟩ / Smelt + code, or a cached popup was reopened.
  void onSmeltRequested() {
    if (!state.isActive) return;
    if (state.step == SmeltGuideStep.selectExpression ||
        state.step == SmeltGuideStep.tapSmelt) {
      state = const SmeltGuideState(
        step: SmeltGuideStep.chooseSmelt,
        isSmelting: true,
      );
      return;
    }
    if (state.step == SmeltGuideStep.chooseSmelt) {
      state = state.copyWith(isSmelting: true, smeltFailed: false);
    }
  }

  void onSmeltEngine(SmeltState smelt) {
    if (!state.isActive) return;

    if (state.step == SmeltGuideStep.chooseSmelt) {
      if (smelt.isLoading) {
        if (!state.isSmelting || state.smeltFailed) {
          state = state.copyWith(isSmelting: true, smeltFailed: false);
        }
        return;
      }
      if (smelt.error != null && smelt.response == null) {
        state = state.copyWith(isSmelting: false, smeltFailed: true);
        return;
      }
      final response = smelt.response;
      if (response != null && state.isSmelting) {
        _afterSmeltResponse(response, smelt.showSteps);
      }
      return;
    }
  }

  void onChatOpened() {
    if (!state.isActive) return;
    if (state.step == SmeltGuideStep.askNext) {
      _go(SmeltGuideStep.chatSelect);
    }
  }

  void onShowStepsTapped() {
    if (!state.isActive) return;
    if (state.step == SmeltGuideStep.showSteps && !state.stepsRevealed) {
      state = state.copyWith(stepsRevealed: true);
    }
  }

  void dismissSoftStep() {
    if (!state.isActive) return;
    if (state.step == SmeltGuideStep.writeProblem) {
      if (state.hasInk) _go(SmeltGuideStep.tapSmelt);
      return;
    }
    if (state.step == SmeltGuideStep.selectExpression) {
      if (state.hasSelection) _go(SmeltGuideStep.chooseSmelt);
      return;
    }
    if (state.step == SmeltGuideStep.showSteps) {
      if (state.stepsRevealed) _go(SmeltGuideStep.askNext);
      return;
    }
    if (state.step == SmeltGuideStep.chatSelect) {
      _go(SmeltGuideStep.enjoy);
      return;
    }
    if (state.step == SmeltGuideStep.enjoy) {
      complete();
    }
  }

  Future<void> skip() async {
    if (!state.step.allowSkip) return;
    state = const SmeltGuideState();
    await _persistCompleted();
  }

  Future<void> complete() async {
    state = const SmeltGuideState();
    await _persistCompleted();
  }

  void _afterSmeltResponse(SmeltResponse response, bool showSteps) {
    final hasAnswer = response.hasDirectAnswer;
    final hasSteps = response.steps.trim().isNotEmpty;
    if (hasAnswer && hasSteps && !showSteps) {
      _go(SmeltGuideStep.showSteps);
      return;
    }
    if (hasSteps) {
      state = const SmeltGuideState(
        step: SmeltGuideStep.showSteps,
        stepsRevealed: true,
      );
      return;
    }
    _go(SmeltGuideStep.askNext);
  }

  void _go(SmeltGuideStep step) {
    if (step == SmeltGuideStep.selectExpression) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setBool(smeltToolHintSeenPrefsKey, true);
      });
    }
    state = SmeltGuideState(
      step: step,
      paused: false,
      hasInk: step == SmeltGuideStep.writeProblem ? state.hasInk : false,
    );
  }
}

final smeltGuideProvider =
    StateNotifierProvider<SmeltGuideNotifier, SmeltGuideState>((ref) {
  return SmeltGuideNotifier();
});

/// Editor sets this when the Smelt action menu is on screen.
final smeltGuideSelectionReadyProvider = StateProvider<bool>((ref) => false);
