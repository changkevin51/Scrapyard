import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/ink_calculator_provider.dart';

/// Handwritten-looking answer sitting just to the right of a detected `=`.
/// Pointers pass through so pen/brush/eraser still hit the canvas.
class InkCalculatorAnswerOverlay extends ConsumerWidget {
  final InkCalculatorResult result;

  const InkCalculatorAnswerOverlay({super.key, required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = result.answerBounds;
    return Positioned(
      left: box.left,
      top: result.baselineY - result.fontSize,
      width: box.width,
      height: result.fontSize * 1.5,
      child: IgnorePointer(
        child: Baseline(
          baseline: result.fontSize,
          baselineType: TextBaseline.alphabetic,
          child: Text(
            result.displayAnswer,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: GoogleFonts.caveat(
              fontSize: result.fontSize,
              height: 1.0,
              color: result.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
