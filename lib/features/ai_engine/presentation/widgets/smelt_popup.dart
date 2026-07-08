import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/smelt_response.dart';
import '../providers/smelt_provider.dart';

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
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Offset _calculatePopupPosition() {
    final rect = widget.selectionRect;
    final screenSize = widget.screenSize;
    const popupWidth = 320.0;
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
          child: TapRegion(
            onTapOutside: (_) => widget.onDismiss(),
            child: _buildCard(state),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(SmeltState state) {
    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: KotoTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KotoTheme.dividers, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: KotoTheme.accent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildContent(state),
            ),
          ),
        ],
      ),
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
            'Analyzing...',
            style: KotoTextStyles.body.copyWith(
              color: KotoTheme.mutedText,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: Colors.redAccent.shade400),
            const SizedBox(width: 8),
            Text(
              'Error',
              style: KotoTextStyles.body.copyWith(
                color: Colors.redAccent.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          error,
          style: KotoTextStyles.caption.copyWith(color: KotoTheme.secondaryText),
        ),
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
              color: KotoTheme.accentSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.functions, size: 18, color: KotoTheme.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: _buildMathAnswer(cleanedAnswer),
                ),
              ],
            ),
          ),
        ] else ...[
          SelectableText(
            response.answer,
            style: KotoTextStyles.body.copyWith(fontSize: 15, height: 1.5),
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
                border: Border.all(color: KotoTheme.dividers),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showSteps ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: KotoTheme.mutedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showSteps ? 'Hide steps' : 'Show steps',
                    style: KotoTextStyles.caption.copyWith(
                      color: KotoTheme.mutedText,
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
                color: KotoTheme.codeSurface,
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
        style: KotoTextStyles.caption.copyWith(
          color: KotoTheme.mutedText,
          fontSize: 9,
          fontStyle: FontStyle.italic,
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
    var cleaned = answer.trim();
    // Remove leading sigma (Σ) or other stray symbols (including LaTeX forms)
    cleaned = cleaned.replaceAll(RegExp(r'^[Σσ∑]\s*'), '');
    // Remove LaTeX sigma at the start: $\Sigma$, \Sigma, etc.
    cleaned = cleaned.replaceAll(RegExp(r'^\$?\\?[Ss]igma\$?\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\\Sigma\s*'), '');
    // Remove any leading/trailing dollar signs
    cleaned = cleaned.replaceAll(RegExp(r'^\$+|\$+$'), '');
    // Trim again after all replacements
    cleaned = cleaned.trim();
    return cleaned;
  }

  /// Build math answer with LaTeX rendering
  Widget _buildMathAnswer(String answer) {
    // Try to render as LaTeX if it contains math expressions
    final latexContent = _extractLatex(answer);
    
    if (latexContent != null) {
      return _LatexDisplay(latex: latexContent);
    }
    
    // Fallback to plain text
    return SelectableText(
      answer,
      style: KotoTextStyles.heading.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: KotoTheme.accent,
      ),
    );
  }

  /// Build math steps with LaTeX rendering
  Widget _buildMathSteps(String steps) {
    return _LatexStepsRenderer(text: steps);
  }

  /// Extract LaTeX content from answer string
  String? _extractLatex(String text) {
    // Check for display math: $$ ... $$ or \[ ... \]
    var match = RegExp(r'\$\$(.+?)\$\$').firstMatch(text);
    if (match != null) return match.group(1);
    
    match = RegExp(r'\\\[(.+?)\\\]').firstMatch(text);
    if (match != null) return match.group(1);
    
    // Check for inline math: $ ... $ or \( ... \)
    match = RegExp(r'\$(.+?)\$').firstMatch(text);
    if (match != null) return match.group(1);
    
    match = RegExp(r'\\\((.+?)\\\)').firstMatch(text);
    if (match != null) return match.group(1);
    
    // If the text looks like a math expression, treat it as LaTeX
    if (RegExp(r'[\\{}^_]|frac|sqrt|pm|int|sum|lim').hasMatch(text)) {
      return text;
    }
    
    return null;
  }
}

/// Widget to display a single LaTeX expression
class _LatexDisplay extends StatelessWidget {
  final String latex;

  const _LatexDisplay({required this.latex});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        latex,
        mathStyle: MathStyle.display,
        textStyle: KotoTextStyles.heading.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: KotoTheme.accent,
        ),
        onErrorFallback: (error) {
          return SelectableText(
            latex,
            style: KotoTextStyles.heading.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KotoTheme.accent,
            ),
          );
        },
      ),
    );
  }
}

/// Renders steps with inline LaTeX support
class _LatexStepsRenderer extends StatelessWidget {
  final String text;

  const _LatexStepsRenderer({required this.text});

  @override
  Widget build(BuildContext context) {
    final segments = _parseLatexSegments(text);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((segment) {
        if (segment.isLatex) {
          // Center all LaTeX equations
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  segment.content,
                  mathStyle: MathStyle.display,
                  textStyle: KotoTextStyles.caption.copyWith(
                    fontSize: 14,
                    color: KotoTheme.bodyText,
                  ),
                  onErrorFallback: (error) {
                    return Text(
                      segment.content,
                      style: KotoTextStyles.caption.copyWith(
                        fontSize: 13,
                        color: KotoTheme.accent,
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        } else {
          // Regular text - could be markdown or plain text
          return _buildTextSegment(segment.content);
        }
      }).toList(),
    );
  }

  Widget _buildTextSegment(String text) {
    final trimmed = text.trim();
    
    // Empty text = spacer
    if (trimmed.isEmpty) {
      return const SizedBox(height: 8);
    }
    
    // Handle bullet points and numbered lists
    if (trimmed.startsWith('-') || trimmed.startsWith('*')) {
      final content = trimmed.substring(1).trim();
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: KotoTextStyles.caption.copyWith(
              fontSize: 13,
              color: KotoTheme.bodyText,
            )),
            Expanded(
              child: _buildRichTextWithItalicNumbers(content),
            ),
          ],
        ),
      );
    }
    
    // Handle numbered lists
    final numberMatch = RegExp(r'^(\d+)\.\s*(.*)').firstMatch(trimmed);
    if (numberMatch != null) {
      final content = numberMatch.group(2) ?? '';
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${numberMatch.group(1)}. ', style: KotoTextStyles.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KotoTheme.primaryText,
            )),
            Expanded(
              child: _buildRichTextWithItalicNumbers(content),
            ),
          ],
        ),
      );
    }
    
    // Handle bold text
    if (text.contains('**')) {
      final parts = text.split('**');
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: KotoTextStyles.caption.copyWith(
              fontSize: 13,
              height: 1.5,
              color: KotoTheme.bodyText,
            ),
            children: parts.asMap().entries.map((entry) {
              if (entry.key % 2 == 1) {
                return TextSpan(
                  text: entry.value,
                  style: KotoTextStyles.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: KotoTheme.primaryText,
                  ),
                );
              }
              return TextSpan(text: entry.value);
            }).toList(),
          ),
        ),
      );
    }
    
    // Plain text with italicized numbers
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _buildRichTextWithItalicNumbers(text),
    );
  }

  /// Build rich text with standalone numbers italicized
  /// Numbers that are part of math expressions (inside $ or \() are NOT italicized
  Widget _buildRichTextWithItalicNumbers(String text) {
    // Split text into parts: math expressions and regular text
    final parts = <_TextPart>[];
    var remaining = text;
    
    while (remaining.isNotEmpty) {
      // Find next math expression
      final mathMatch = RegExp(r'\$\$[^$]+\$\$|\\\[.*?\\\]|\\\([^)]*\\\)|\$[^$]+\$').firstMatch(remaining);
      
      if (mathMatch == null) {
        // No more math - rest is regular text
        parts.add(_TextPart(content: remaining, isMath: false));
        break;
      }
      
      // Add text before math
      if (mathMatch.start > 0) {
        parts.add(_TextPart(content: remaining.substring(0, mathMatch.start), isMath: false));
      }
      // Add math expression
      parts.add(_TextPart(content: mathMatch.group(0)!, isMath: true));
      remaining = remaining.substring(mathMatch.end);
    }
    
    if (parts.isEmpty) {
      return Text(
        text,
        style: KotoTextStyles.caption.copyWith(
          fontSize: 13,
          height: 1.5,
          color: KotoTheme.bodyText,
        ),
      );
    }
    
    return RichText(
      text: TextSpan(
        style: KotoTextStyles.caption.copyWith(
          fontSize: 13,
          height: 1.5,
          color: KotoTheme.bodyText,
        ),
        children: parts.map((part) {
          if (part.isMath) {
            // Keep math as-is (it will be rendered by LaTeX renderer separately)
            return TextSpan(text: part.content);
          } else {
            // Italicize standalone numbers in regular text
            return _italicizeNumbers(part.content);
          }
        }).toList(),
      ),
    );
  }

  /// Italicize standalone numbers in text (but not numbers that are part of words)
  TextSpan _italicizeNumbers(String text) {
    // Match standalone numbers (including negative and decimals)
    // A standalone number is preceded by space/start and followed by space/end/punctuation
    final numberRegex = RegExp(r'(?<!\w)(-?\d+\.?\d*)(?!\w)');
    
    final spans = <TextSpan>[];
    var lastEnd = 0;
    
    for (final match in numberRegex.allMatches(text)) {
      // Add text before the number
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      // Add italicized number
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
      lastEnd = match.end;
    }
    
    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    
    if (spans.isEmpty) {
      return TextSpan(text: text);
    }
    
    return TextSpan(children: spans);
  }

  /// Parse text into segments of regular text and LaTeX
  List<_TextSegment> _parseLatexSegments(String input) {
    final segments = <_TextSegment>[];
    
    // Split by lines first to handle multi-line content
    final lines = input.split('\n');
    
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Check for display math: $$ ... $$ or \[ ... \]
      final displayMathRegex = RegExp(r'\$\$(.+?)\$\$|\\\[(.+?)\\\]');
      var displayMatch = displayMathRegex.firstMatch(line);
      
      if (displayMatch != null) {
        final latex = displayMatch.group(1) ?? displayMatch.group(2) ?? '';
        final before = line.substring(0, displayMatch.start);
        final after = line.substring(displayMatch.end);
        
        if (before.isNotEmpty) {
          segments.add(_TextSegment(content: before, isLatex: false));
        }
        segments.add(_TextSegment(content: latex, isLatex: true));
        if (after.isNotEmpty) {
          segments.add(_TextSegment(content: after, isLatex: false));
        }
      } else {
        // Check for inline math: $ ... $ or \( ... \)
        final inlineMathRegex = RegExp(r'\$(.+?)\$|\\\((.+?)\\\)');
        var remaining = line;
        var hasInlineMath = false;
        
        while (remaining.isNotEmpty) {
          final match = inlineMathRegex.firstMatch(remaining);
          if (match == null) {
            if (remaining.isNotEmpty) {
              segments.add(_TextSegment(content: remaining, isLatex: false));
            }
            break;
          }
          
          hasInlineMath = true;
          final latex = match.group(1) ?? match.group(2) ?? '';
          final before = remaining.substring(0, match.start);
          
          if (before.isNotEmpty) {
            segments.add(_TextSegment(content: before, isLatex: false));
          }
          segments.add(_TextSegment(content: latex, isLatex: true));
          remaining = remaining.substring(match.end);
        }
        
        if (!hasInlineMath) {
          segments.add(_TextSegment(content: line, isLatex: false));
        }
      }
      
      // Add empty segment for line break (except last line)
      if (i < lines.length - 1) {
        segments.add(_TextSegment(content: '', isLatex: false));
      }
    }
    
    return segments;
  }

}

class _TextSegment {
  final String content;
  final bool isLatex;

  _TextSegment({required this.content, required this.isLatex});
}

class _TextPart {
  final String content;
  final bool isMath;

  _TextPart({required this.content, required this.isMath});
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
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: KotoTheme.accent.withValues(alpha: 0.3 + opacity * 0.7),
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
  late Animation<double> _pulseAnim;
  late Animation<double> _dashAnim;

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

    _pulseAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _dashAnim = Tween<double>(begin: 0, end: 1).animate(_dashController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use Positioned.fromRect to position the overlay exactly at the selection rect
    return Positioned.fromRect(
      rect: widget.selectionRect,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _dashController]),
          builder: (context, _) {
            return CustomPaint(
              size: widget.selectionRect.size,
              painter: _ThinkingBorderPainter(
                pulseOpacity: _pulseAnim.value,
                dashOffset: _dashAnim.value,
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

  _ThinkingBorderPainter({
    required this.pulseOpacity,
    required this.dashOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    
    // Soft glow fill
    final fillPaint = Paint()
      ..color = KotoTheme.accent.withValues(alpha: pulseOpacity * 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      fillPaint,
    );

    // Animated dashed border
    final borderPaint = Paint()
      ..color = KotoTheme.accent.withValues(alpha: pulseOpacity)
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
      old.pulseOpacity != pulseOpacity || old.dashOffset != dashOffset;
}