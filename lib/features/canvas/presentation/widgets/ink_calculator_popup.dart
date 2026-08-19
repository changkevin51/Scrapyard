import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../ai_engine/presentation/widgets/latex_markdown_view.dart';
import '../../../ai_engine/presentation/widgets/smelt_action_menu.dart';
import '../providers/ink_calculator_provider.dart';

/// Small paper chit shown when the user taps a solved on-device expression.
class InkCalculatorPopup extends StatelessWidget {
  final InkCalculatorResult result;
  final Rect selectionRect;
  final Size screenSize;
  final VoidCallback onDismiss;
  final VoidCallback onRemoveAnswer;
  final VoidCallback onUseSmelt;

  const InkCalculatorPopup({
    super.key,
    required this.result,
    required this.selectionRect,
    required this.screenSize,
    required this.onDismiss,
    required this.onRemoveAnswer,
    required this.onUseSmelt,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 268.0;
    final below = selectionRect.bottom + 12;
    final fitsBelow = below + 220 < screenSize.height - 16;
    final top = fitsBelow
        ? below
        : math.max(16.0, selectionRect.top - 200);
    final left = (selectionRect.left)
        .clamp(16.0, math.max(16.0, screenSize.width - cardWidth - 16))
        .toDouble();

    final decimal = result.decimalAnswer;
    final latex = decimal == null
        ? '${result.latex} = ${result.answerLatex}'
        : '${result.latex} = ${result.answerLatex} = $decimal';

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: cardWidth,
          child: PaperChit(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ScrapStampLabel(text: '⟨ Quick Calc ⟩'),
                  const SizedBox(height: 10),
                  LatexDisplay(
                    latex: latex,
                    fontSize: 18,
                    color: ScrapTheme.primaryText,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'On-device detection was used. This is a beta feature and is only trained for simple arithmetic.',
                    style: ScrapTextStyles.caption.copyWith(
                      color: ScrapTheme.mutedText,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      PaperMenuChip(
                        label: '⟨ Smelt ⟩ instead',
                        tone: PaperMenuChipTone.primary,
                        onTap: onUseSmelt,
                      ),
                      PaperMenuChip(
                        label: 'Remove answer',
                        tone: PaperMenuChipTone.ghost,
                        onTap: onRemoveAnswer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Disable this in Canvas settings → Quick calc.',
                    style: ScrapTextStyles.stamp.copyWith(
                      color: ScrapTheme.mutedText,
                      fontSize: 9,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Debug-only chit: model's guessed LaTeX when on-device calc fired but failed.
class InkCalculatorDebugPopup extends StatelessWidget {
  final InkCalcDebugGuess guess;
  final VoidCallback onDismiss;

  const InkCalculatorDebugPopup({
    super.key,
    required this.guess,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 280.0;
    final latex = guess.latex.trim();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            child: SizedBox(
              width: cardWidth,
              child: PaperChit(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ScrapStampLabel(text: '⟨ Debug ⟩'),
                      const SizedBox(height: 10),
                      Text(
                        'Model saw',
                        style: ScrapTextStyles.caption.copyWith(
                          color: ScrapTheme.mutedText,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        latex.isEmpty ? '(empty)' : latex,
                        style: ScrapTextStyles.body.copyWith(
                          fontFamily: 'Courier Prime',
                          fontSize: 15,
                          color: ScrapTheme.primaryText,
                        ),
                      ),
                      if (latex.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        LatexDisplay(
                          latex: latex,
                          fontSize: 18,
                          color: ScrapTheme.primaryText,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        guess.reason,
                        style: ScrapTextStyles.caption.copyWith(
                          color: ScrapTheme.mutedText,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (guess.strokeCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${guess.strokeCount} strokes in crop (orange box)',
                          style: ScrapTextStyles.caption.copyWith(
                            color: ScrapTheme.mutedText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
