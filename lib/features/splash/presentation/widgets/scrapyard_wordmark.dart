import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';

/// Animation state for the "Scrapyard" wordmark under the logo.
class WordmarkAnimState {
  const WordmarkAnimState({
    required this.letters,
    this.tracking = 1,
    this.underline = 1,
    this.blockOpacity = 1,
    this.showCaret = false,
  });

  final List<double> letters;
  final double tracking;
  final double underline;
  final double blockOpacity;
  final bool showCaret;

  static const word = 'Scrapyard';

  static final settled = WordmarkAnimState(
    letters: List<double>.filled(word.length, 1),
  );

  static final hidden = WordmarkAnimState(
    letters: List<double>.filled(word.length, 0),
    tracking: 0,
    underline: 0,
    blockOpacity: 0,
  );
}

/// Choreographs the wordmark against the full splash timeline [t] (0–1).
///
/// Starts with the mouth draw so logo + wordmark overlap as one beat.
WordmarkAnimState wordmarkAnimAt(double t) {
  double seg(double start, double end, Curve curve) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform((t - start) / (end - start));
  }

  const word = WordmarkAnimState.word;
  final letters = <double>[];
  // Mouth begins at logoT 0.70 → absolute t ≈ 0.43 with logoShare 0.62.
  const typeStart = 0.43;
  const typeEnd = 0.82;
  const span = typeEnd - typeStart;
  const perLetter = span / WordmarkAnimState.word.length;

  for (var i = 0; i < word.length; i++) {
    final start = typeStart + i * perLetter * 0.85;
    final end = start + perLetter * 1.35;
    letters.add(seg(start, end, Curves.easeOutCubic));
  }

  final tracking = seg(0.45, 0.90, Curves.easeOutCubic);
  final underline = seg(0.78, 0.94, Curves.easeInOutCubic);
  final blockOpacity = seg(0.41, 0.47, Curves.easeOut);
  final typing = t >= typeStart && t < typeEnd + 0.02;

  return WordmarkAnimState(
    letters: letters,
    tracking: tracking,
    underline: underline,
    blockOpacity: blockOpacity,
    showCaret: typing,
  );
}

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

/// Courier Prime wordmark with typewriter lettering + ink underline.
class ScrapyardWordmark extends StatelessWidget {
  const ScrapyardWordmark({
    super.key,
    required this.state,
    this.fontSize = 36,
    this.color = ScrapTheme.primaryText,
  });

  final WordmarkAnimState state;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final letterSpacing = _lerp(8.0, 1.5, state.tracking);
    final style = TextStyle(
      fontFamily: 'Courier Prime',
      fontWeight: FontWeight.w700,
      fontSize: fontSize,
      height: 1.0,
      letterSpacing: letterSpacing,
      color: color,
      decoration: TextDecoration.none,
    );

    final underlineThickness = math.max(2.0, fontSize * 0.055);
    final underlineProgress = state.underline.clamp(0.0, 1.0);

    return Opacity(
      opacity: state.blockOpacity.clamp(0.0, 1.0),
      child: SelectionContainer.disabled(
        child: Semantics(
          // Keep browser spell-check / Grammarly off the animated wordmark.
          excludeSemantics: true,
          child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10 + underlineThickness),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < WordmarkAnimState.word.length; i++)
                  _Letter(
                    char: WordmarkAnimState.word[i],
                    progress: state.letters[i],
                    style: style,
                  ),
                if (state.showCaret) _Caret(height: fontSize * 0.92, color: color),
              ],
            ),
          ),
          if (underlineProgress > 0)
            Positioned(
              left: 0,
              right: state.showCaret ? 8 : 0,
              bottom: 0,
              height: underlineThickness,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: underlineProgress,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(underlineThickness),
                    ),
                  ),
                ),
              ),
            ),
        ],
          ),
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({
    required this.char,
    required this.progress,
    required this.style,
  });

  final String char;
  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(p);
    final dy = (1 - p) * 10;
    final scale = 0.86 + 0.14 * pop.clamp(0.0, 1.2);

    return Opacity(
      opacity: Curves.easeOut.transform(p),
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Text(char, style: style),
        ),
      ),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        return Opacity(
          opacity: 0.25 + 0.75 * _blink.value,
          child: Container(
            margin: const EdgeInsets.only(left: 2, bottom: 2),
            width: 2.5,
            height: widget.height,
            color: widget.color,
          ),
        );
      },
    );
  }
}
