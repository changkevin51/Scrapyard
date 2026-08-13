/// Ordered Smelt coach-tour steps. [idle] means the tour is not showing.
enum SmeltGuideStep {
  idle,
  openScrap,
  writeProblem,
  tapSmelt,
  selectExpression,
  chooseSmelt,
  showSteps,
  askNext,
  chatSelect,
  enjoy,
}

enum SmeltGuideMode {
  /// Dim the rest of the UI; the user should hit the spotlighted control.
  gated,

  /// Message only (or canvas stays free). Dismiss / Next / skip as configured.
  soft,
}

extension SmeltGuideStepX on SmeltGuideStep {
  bool get isActive => this != SmeltGuideStep.idle;

  bool get isEditorStep => switch (this) {
        SmeltGuideStep.idle || SmeltGuideStep.openScrap => false,
        _ => true,
      };

  bool get allowSkip =>
      isEditorStep && this != SmeltGuideStep.chatSelect;

  SmeltGuideMode get mode => switch (this) {
        SmeltGuideStep.openScrap ||
        SmeltGuideStep.tapSmelt ||
        SmeltGuideStep.chooseSmelt ||
        SmeltGuideStep.showSteps ||
        SmeltGuideStep.askNext =>
          SmeltGuideMode.gated,
        _ => SmeltGuideMode.soft,
      };

  bool get usesBarrier => mode == SmeltGuideMode.gated;

  bool get showArrowToAnswer => this == SmeltGuideStep.showSteps;

  /// Editor-only index for `⟨ n of 8 ⟩`. Null on the Home spotlight.
  int? get editorOrdinal => switch (this) {
        SmeltGuideStep.writeProblem => 1,
        SmeltGuideStep.tapSmelt => 2,
        SmeltGuideStep.selectExpression => 3,
        SmeltGuideStep.chooseSmelt => 4,
        SmeltGuideStep.showSteps => 5,
        SmeltGuideStep.askNext => 6,
        SmeltGuideStep.chatSelect => 7,
        SmeltGuideStep.enjoy => 8,
        _ => null,
      };

  static const editorStepCount = 8;

  String get stampLabel {
    final n = editorOrdinal;
    if (n == null) return '⟨ scrapyard ⟩';
    return '⟨ $n of $editorStepCount ⟩';
  }

  String get body {
    switch (this) {
      case SmeltGuideStep.idle:
        return '';
      case SmeltGuideStep.openScrap:
        return 'Your first scrap is waiting — tap here.';
      case SmeltGuideStep.writeProblem:
        return 'Scribble an equation or a problem.';
      case SmeltGuideStep.tapSmelt:
        return 'Now tap ⟨ Smelt ⟩.';
      case SmeltGuideStep.selectExpression:
        return 'Tap the writing. If it didn’t select properly, drag around the equation.';
      case SmeltGuideStep.chooseSmelt:
        return '⟨ Smelt ⟩ for a walkthrough, or Smelt + code to check the math.';
      case SmeltGuideStep.showSteps:
        return "That's the answer. Tap Show steps to see the work.";
      case SmeltGuideStep.askNext:
        return 'Tap a question to keep chatting (or ask your own).';
      case SmeltGuideStep.chatSelect:
        return 'Use the select button to attach anything on the scrap.';
      case SmeltGuideStep.enjoy:
        return "That's the lot. The paper's yours.";
    }
  }

  SmeltGuideStep get next {
    switch (this) {
      case SmeltGuideStep.idle:
        return SmeltGuideStep.idle;
      case SmeltGuideStep.openScrap:
        return SmeltGuideStep.writeProblem;
      case SmeltGuideStep.writeProblem:
        return SmeltGuideStep.tapSmelt;
      case SmeltGuideStep.tapSmelt:
        return SmeltGuideStep.selectExpression;
      case SmeltGuideStep.selectExpression:
        return SmeltGuideStep.chooseSmelt;
      case SmeltGuideStep.chooseSmelt:
        return SmeltGuideStep.showSteps;
      case SmeltGuideStep.showSteps:
        return SmeltGuideStep.askNext;
      case SmeltGuideStep.askNext:
        return SmeltGuideStep.chatSelect;
      case SmeltGuideStep.chatSelect:
        return SmeltGuideStep.enjoy;
      case SmeltGuideStep.enjoy:
        return SmeltGuideStep.idle;
    }
  }
}
