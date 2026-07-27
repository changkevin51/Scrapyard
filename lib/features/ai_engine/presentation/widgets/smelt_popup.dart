import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import '../../_debug_log_helper.dart';
import '../providers/smelt_provider.dart';
import 'api_key_dialog.dart';

/// Popup widget that displays the smelt AI response
class SmeltPopup extends ConsumerStatefulWidget {
  final Rect selectionRect;
  final VoidCallback onDismiss;
  final Size screenSize;

  const SmeltPopup({
    super.key,
    required this.selectionRect,
    required this.onDismiss,
    required this.screenSize,
  });

  @override
  ConsumerState<SmeltPopup> createState() => _SmeltPopupState();
}

class _SmeltPopupState extends ConsumerState<SmeltPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _rotateAnim = Tween<double>(begin: -1.2 * math.pi / 180, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Preferred popup width; grows for math, capped so it fits the screen.
  double _popupWidth() {
    const margin = 16.0;
    const preferred = 420.0;
    const maxWidth = 480.0;
    final available = widget.screenSize.width - (margin * 2);
    return math.min(maxWidth, math.min(preferred, available));
  }

  Offset _calculatePopupPosition() {
    final rect = widget.selectionRect;
    final screenSize = widget.screenSize;
    final popupWidth = _popupWidth();
    const popupMinHeight = 100.0;
    const margin = 16.0;

    // Try below the selection first
    double top = rect.bottom + 12;
    double left = rect.center.dx - popupWidth / 2;

    // If not enough space below, go above
    if (top + popupMinHeight > screenSize.height - margin) {
      top = rect.top - popupMinHeight - 12;
    }

    // Clamp to screen
    if (top < margin) top = margin;
    if (left < margin) left = margin;
    if (left + popupWidth > screenSize.width - margin) {
      left = screenSize.width - popupWidth - margin;
    }

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smeltProvider);
    final position = _calculatePopupPosition();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _rotateAnim,
            builder: (context, child) => Transform.rotate(
              angle: _rotateAnim.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: TapRegion(
              onTapOutside: (_) => widget.onDismiss(),
              child: _buildCard(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(SmeltState state) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _popupWidth(),
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: ScrapTheme.cardSurface,
            borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            border: Border.all(color: ScrapTheme.dividers, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000), // ~5% black
                offset: Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tape strip header
              Transform.rotate(
                angle: -1.5 * math.pi / 180,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ScrapTheme.tape,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: ScrapTheme.kraft.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  child: const Center(
                    child: ScrapStampLabel(
                      text: '⟨ Smelt ⟩',
                      tiltDegrees: 0,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: _buildContent(state),
                ),
              ),
            ],
          ),
        ),
        // Torn bottom deckle — page colour notches so the slip looks torn
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 10,
          child: IgnorePointer(
            child: CustomPaint(
              painter: TornEdgePainter(
                seed: 42,
                amplitude: 3.5,
                fillColor: Color(0xFFF5F4F0), // ScrapTheme.background
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(SmeltState state) {
    if (state.isLoading) {
      return _buildLoadingState();
    }
    if (state.error != null) {
      return _buildErrorState(state.error!);
    }
    if (state.response == null) {
      return const SizedBox();
    }
    return _buildResponseContent(state.response!, state.showSteps);
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const _ThinkingDots(),
          const SizedBox(width: 12),
          Text(
            'Smelting...',
            style: ScrapTextStyles.body.copyWith(
              color: ScrapTheme.mutedText,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final isMissingKey = error.contains(SmeltService.missingApiKeyMessage) ||
        error.contains('No Gemini API key');

    // Strip the "Exception: " prefix for display.
    final displayError = error.startsWith('Exception: ')
        ? error.substring('Exception: '.length)
        : error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: Colors.redAccent.shade400),
            const SizedBox(width: 8),
            Text(
              isMissingKey ? 'API key needed' : 'Error',
              style: ScrapTextStyles.body.copyWith(
                color: Colors.redAccent.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isMissingKey
              ? SmeltService.missingApiKeyMessage
              : displayError,
          style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.secondaryText),
        ),
        if (isMissingKey) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              final saved = await showApiKeyDialog(context, allowSkip: false);
              if (saved == true && mounted) {
                ref.read(smeltProvider.notifier).clearState();
              }
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Add key',
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResponseContent(SmeltResponse response, bool showSteps) {
    // Clean the answer - remove stray sigma or other unwanted characters
    final cleanedAnswer = _cleanAnswer(response.answer);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (response.isMath) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ScrapTheme.accentSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildMathAnswer(cleanedAnswer),
          ),
        ] else ...[
          SelectableText(
            response.answer,
            style: ScrapTextStyles.body.copyWith(fontSize: 15, height: 1.5),
          ),
        ],
        if (response.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => ref.read(smeltProvider.notifier).toggleSteps(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ScrapTheme.dividers),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showSteps ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: ScrapTheme.mutedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showSteps ? 'Hide steps' : 'Show steps',
                    style: ScrapTextStyles.caption.copyWith(
                      color: ScrapTheme.mutedText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showSteps) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ScrapTheme.codeSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildMathSteps(response.steps),
            ),
          ],
        ],
        const SizedBox(height: 8),
        _buildModelFinePrint(response.modelUsed),
      ],
    );
  }

  /// Build fine print showing which Gemini model was used
  Widget _buildModelFinePrint(String modelUsed) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        'Powered by ${_formatModelName(modelUsed)}',
        style: ScrapTextStyles.stamp.copyWith(
          color: ScrapTheme.mutedText,
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  /// Format model name for display (e.g., "gemini-2.0-flash-exp" -> "Gemini 2.0 Flash")
  String _formatModelName(String model) {
    if (model.contains('gemini')) {
      return model.split('-').map((part) {
        if (RegExp(r'^\d').hasMatch(part)) return part; // Keep version numbers as-is
        if (part.isEmpty) return '';
        return part[0].toUpperCase() + part.substring(1);
      }).where((part) => part.isNotEmpty).join(' ');
    }
    return model;
  }

  /// Clean the answer by removing stray characters like sigma
  String _cleanAnswer(String answer) {
    return _prepareAnswerLatex(answer);
  }

  /// Strip math delimiters and leading sigma, then normalize for KaTeX.
  String _prepareAnswerLatex(String answer) {
    var latex = answer.trim();
    latex = _stripMathDelimiters(latex);
    latex = _stripLeadingSigma(latex);
    latex = latex.replaceAll(RegExp(r'^\$+|\$+$'), '').trim();
    return _normalizeUnicodeMath(latex);
  }

  String _stripMathDelimiters(String text) {
    var t = text.trim();
    if (t.startsWith(r'$$') && t.endsWith(r'$$') && t.length > 4) {
      return t.substring(2, t.length - 2).trim();
    }
    if (t.startsWith(r'\[') && t.endsWith(r'\]') && t.length > 4) {
      return t.substring(2, t.length - 2).trim();
    }
    if (t.startsWith(r'\(') && t.endsWith(r'\)') && t.length > 4) {
      return t.substring(2, t.length - 2).trim();
    }
    if (t.startsWith(r'$') && t.endsWith(r'$') && t.length > 2) {
      return t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  String _stripLeadingSigma(String text) {
    var cleaned = text.trim();
    while (true) {
      final before = cleaned;
      cleaned = cleaned.replaceAll(RegExp(r'^[Σσ∑]\s*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'^\$?\\?[Ss]igma\$?\s*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'^\\Sigma\s*'), '');
      cleaned = cleaned.trim();
      if (cleaned == before) break;
    }
    return cleaned;
  }

  String _normalizeUnicodeMath(String text) {
    return text
        .replaceAll('π', r'\pi')
        .replaceAll('θ', r'\theta')
        .replaceAll('∞', r'\infty')
        .replaceAll('±', r'\pm')
        .replaceAll('×', r'\times')
        .replaceAll('÷', r'\div');
  }

  /// Build math answer with LaTeX rendering
  Widget _buildMathAnswer(String answer) {
    return _LatexDisplay(latex: answer);
  }

  /// Build math steps with LaTeX rendering
  Widget _buildMathSteps(String steps) {
    return _LatexStepsRenderer(text: steps);
  }
}

/// Widget to display a single LaTeX expression
class _LatexDisplay extends StatelessWidget {
  final String latex;

  const _LatexDisplay({required this.latex});

  /// [inherit: false] prevents DefaultTextStyle (Noto) from merging into KaTeX.
  static const _mathTextStyle = TextStyle(
    inherit: false,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.normal,
    color: ScrapTheme.accent,
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        latex,
        mathStyle: MathStyle.display,
        textStyle: _mathTextStyle,
        onErrorFallback: (error) {
          return SelectableText(
            latex,
            style: _mathTextStyle,
          );
        },
      ),
    );
  }
}

int _latexStepsBuildCount = 0;

/// Renders steps with true inline LaTeX (WidgetSpan) and centered display math.
class _LatexStepsRenderer extends StatelessWidget {
  final String text;

  const _LatexStepsRenderer({required this.text});

  static final _baseTextStyle = TextStyle(
    inherit: false,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.normal,
    color: ScrapTheme.bodyText,
    // Prose uses the app caption font; math widgets use KaTeX via Math.tex.
    fontFamily: ScrapTextStyles.caption.fontFamily,
  );

  static const _mathOnlyStyle = TextStyle(
    inherit: false,
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.normal,
    color: ScrapTheme.bodyText,
  );

  @override
  Widget build(BuildContext context) {
    final lines = _coalesceOrphanBullets(text.split('\n'));

    // #region agent log
    _latexStepsBuildCount++;
    dlog('H5_build_count', '_LatexStepsRenderer.build() invocation count', {
      'buildCount': _latexStepsBuildCount,
      'inputTextJsonEncoded': jsonEncode(text),
      'lineCount': lines.length,
    });
    // #endregion

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) _buildLine(lines[i]),
      ],
    );
  }

  /// Merge `-` / `*` alone on a line with the following math-only line so
  /// equations sit on the same row as the bullet.
  List<String> _coalesceOrphanBullets(List<String> lines) {
    final result = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      final isOrphanBullet = RegExp(r'^[-*•]\s*$').hasMatch(trimmed);
      if (isOrphanBullet && i + 1 < lines.length) {
        final next = lines[i + 1].trim();
        if (_isMathOnlyLine(next)) {
          result.add('- ${_asInlineMathLine(next)}');
          i++;
          continue;
        }
      }
      result.add(lines[i]);
    }
    return result;
  }

  bool _isMathOnlyLine(String line) {
    final tokens = _parseLineTokens(line);
    if (tokens.isEmpty) return false;
    return tokens.every(
      (t) =>
          t.kind == _TokenKind.inlineMath ||
          t.kind == _TokenKind.displayMath ||
          (t.kind == _TokenKind.text && t.content.trim().isEmpty),
    );
  }

  /// Prefer inline delimiters so bullet math stays on one line.
  String _asInlineMathLine(String line) {
    return line
        .replaceAllMapped(
          RegExp(r'\$\$(.+?)\$\$', dotAll: true),
          (m) => '\\(${m.group(1)}\\)',
        )
        .replaceAllMapped(
          RegExp(r'\\\[(.+?)\\\]', dotAll: true),
          (m) => '\\(${m.group(1)}\\)',
        );
  }

  Widget _buildLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return const SizedBox(height: 8);
    }

    final tokens = _parseLineTokens(trimmed);

    // Standalone display math → scrollable block on its own line
    final onlyDisplay = tokens.length == 1 &&
        tokens.single.kind == _TokenKind.displayMath;
    if (onlyDisplay) {
      return _buildDisplayMath(tokens.single.content);
    }

    // Bullet list
    if (trimmed.startsWith('-') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('•')) {
      final body = trimmed.substring(1).trimLeft();
      return _buildBulletRow(body);
    }

    // Numbered list
    final numberMatch = RegExp(r'^(\d+)\.\s*(.*)').firstMatch(trimmed);
    if (numberMatch != null) {
      final body = numberMatch.group(2) ?? '';
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${numberMatch.group(1)}. ',
              style: _baseTextStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: ScrapTheme.primaryText,
              ),
            ),
            Expanded(child: _buildInlineOrMathOnly(body)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _buildInlineRich(tokens),
    );
  }

  Widget _buildBulletRow(String body) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('• ', style: _baseTextStyle),
          Expanded(child: _buildInlineOrMathOnly(body)),
        ],
      ),
    );
  }

  /// Math-only bodies sit in a Row (not WidgetSpan) so they stay beside the bullet.
  Widget _buildInlineOrMathOnly(String body) {
    final tokens = _parseLineTokens(body);
    final mathTokens = tokens
        .where((t) =>
            t.kind == _TokenKind.inlineMath ||
            t.kind == _TokenKind.displayMath)
        .toList();
    final hasProse = tokens.any(
      (t) => t.kind == _TokenKind.text && t.content.trim().isNotEmpty,
    );

    if (!hasProse && mathTokens.length == 1) {
      return _buildScrollableMath(mathTokens.single.content);
    }
    return _buildInlineRich(tokens);
  }

  Widget _buildScrollableMath(String latex) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        latex,
        mathStyle: MathStyle.text,
        textStyle: _mathOnlyStyle,
        onErrorFallback: (_) => Text(
          latex,
          style: _mathOnlyStyle.copyWith(color: ScrapTheme.accent),
        ),
      ),
    );
  }

  Widget _buildDisplayMath(String latex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Center(
                child: Math.tex(
                  latex,
                  mathStyle: MathStyle.display,
                  textStyle: _mathOnlyStyle.copyWith(fontSize: 14),
                  onErrorFallback: (_) => Text(
                    latex,
                    style: _mathOnlyStyle.copyWith(
                      fontSize: 14,
                      color: ScrapTheme.accent,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Mix of prose + inline (and mid-sentence display) math on one line.
  Widget _buildInlineRich(List<_LineToken> tokens) {
    if (tokens.isEmpty) {
      return const SizedBox.shrink();
    }

    final spans = <InlineSpan>[];
    for (final token in tokens) {
      switch (token.kind) {
        case _TokenKind.text:
          spans.addAll(_textSpansWithBoldAndItalics(token.content));
        case _TokenKind.inlineMath:
        case _TokenKind.displayMath:
          // Mid-sentence display delimiters still render inline so they
          // don't break the line.
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                token.content,
                mathStyle: MathStyle.text,
                textStyle: _mathOnlyStyle,
                onErrorFallback: (_) => Text(
                  token.content,
                  style: _mathOnlyStyle.copyWith(color: ScrapTheme.accent),
                ),
              ),
            ),
          );
      }
    }

    return Text.rich(
      TextSpan(style: _baseTextStyle, children: spans),
    );
  }

  /// Split a line into text / inline-math / display-math tokens.
  List<_LineToken> _parseLineTokens(String line) {
    final tokens = <_LineToken>[];
    // Order matters: $$ and \[ \] before $ and \( \)
    final mathRegex = RegExp(
      r'\$\$(.+?)\$\$|\\\[(.+?)\\\]|\\\((.+?)\\\)|\$(.+?)\$',
      dotAll: true,
    );

    var start = 0;
    for (final match in mathRegex.allMatches(line)) {
      if (match.start > start) {
        tokens.add(_LineToken(
          content: line.substring(start, match.start),
          kind: _TokenKind.text,
        ));
      }

      final isDisplay =
          match.group(1) != null || match.group(2) != null;
      final latex =
          match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      tokens.add(_LineToken(
        content: latex,
        kind: isDisplay ? _TokenKind.displayMath : _TokenKind.inlineMath,
      ));
      start = match.end;
    }

    if (start < line.length) {
      tokens.add(_LineToken(
        content: line.substring(start),
        kind: _TokenKind.text,
      ));
    }

    return tokens;
  }

  /// Bold (`**...**`) + italicize standalone numbers in prose.
  List<InlineSpan> _textSpansWithBoldAndItalics(String text) {
    if (!text.contains('**')) {
      return [_italicizeNumbers(text)];
    }

    final spans = <InlineSpan>[];
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      if (i.isOdd) {
        spans.add(TextSpan(
          style: _baseTextStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: ScrapTheme.primaryText,
          ),
          children: [_italicizeNumbers(part)],
        ));
      } else {
        spans.add(_italicizeNumbers(part));
      }
    }
    return spans;
  }

  /// Italicize standalone numbers (not part of words).
  TextSpan _italicizeNumbers(String text) {
    final numberRegex = RegExp(r'(?<!\w)(-?\d+\.?\d*)(?!\w)');
    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (final match in numberRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    if (spans.isEmpty) {
      return TextSpan(text: text);
    }
    if (spans.length == 1) {
      return spans.single;
    }
    return TextSpan(children: spans);
  }
}

enum _TokenKind { text, inlineMath, displayMath }

class _LineToken {
  final String content;
  final _TokenKind kind;

  const _LineToken({required this.content, required this.kind});
}

/// Animated thinking dots for loading state
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ember = Color(0xFF8A6A55);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final progress = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity =
                progress < 0.5 ? progress * 2 : 2 - progress * 2;
            // Stagger accent → ember for a furnace glow
            final color = Color.lerp(ScrapTheme.accent, ember, index / 2)!;
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Animated bounding box overlay shown while smelt is processing
class SmeltThinkingOverlay extends StatefulWidget {
  final Rect selectionRect;

  const SmeltThinkingOverlay({super.key, required this.selectionRect});

  @override
  State<SmeltThinkingOverlay> createState() => _SmeltThinkingOverlayState();
}

class _SmeltThinkingOverlayState extends State<SmeltThinkingOverlay>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _dashController;
  late AnimationController _scanController;
  late Animation<double> _pulseAnim;
  late Animation<double> _dashAnim;
  late Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _dashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _dashAnim = Tween<double>(begin: 0, end: 1).animate(_dashController);
    _scanAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dashController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: widget.selectionRect,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pulseController,
            _dashController,
            _scanController,
          ]),
          builder: (context, _) {
            return CustomPaint(
              size: widget.selectionRect.size,
              painter: _ThinkingBorderPainter(
                pulseOpacity: _pulseAnim.value,
                dashOffset: _dashAnim.value,
                scanProgress: _scanAnim.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ThinkingBorderPainter extends CustomPainter {
  final double pulseOpacity;
  final double dashOffset;
  final double scanProgress;

  _ThinkingBorderPainter({
    required this.pulseOpacity,
    required this.dashOffset,
    required this.scanProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Soft glow fill
    final fillPaint = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: pulseOpacity * 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );

    // Scan sweep — one thin gradient band traversing top → bottom
    final bandH = math.max(8.0, size.height * 0.12);
    final y = (size.height + bandH) * scanProgress - bandH;
    final sweepRect = Rect.fromLTWH(0, y, size.width, bandH);
    final sweepPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ScrapTheme.accent.withValues(alpha: 0.0),
          ScrapTheme.accent.withValues(alpha: 0.18),
          ScrapTheme.accent.withValues(alpha: 0.0),
        ],
      ).createShader(sweepRect);
    canvas.drawRect(sweepRect.intersect(rect), sweepPaint);

    // Animated dashed border
    final borderPaint = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: pulseOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    _drawAnimatedDashedRect(canvas, rect, borderPaint, dashOffset);
  }

  void _drawAnimatedDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double offset,
  ) {
    const dashLen = 8.0;
    const gapLen = 6.0;
    const totalDash = dashLen + gapLen;

    void drawSide(Offset start, Offset end) {
      final length = (end - start).distance;
      if (length == 0) return;
      final dir = (end - start) / length;
      final shift = offset * totalDash;
      double d = -shift % totalDash;
      while (d < length) {
        final segEnd = math.min(d + dashLen, length);
        if (segEnd > 0 && d < length) {
          canvas.drawLine(
            start + dir * math.max(d, 0),
            start + dir * segEnd,
            paint,
          );
        }
        d += totalDash;
      }
    }

    drawSide(rect.topLeft, rect.topRight);
    drawSide(rect.topRight, rect.bottomRight);
    drawSide(rect.bottomRight, rect.bottomLeft);
    drawSide(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _ThinkingBorderPainter old) =>
      old.pulseOpacity != pulseOpacity ||
      old.dashOffset != dashOffset ||
      old.scanProgress != scanProgress;
}