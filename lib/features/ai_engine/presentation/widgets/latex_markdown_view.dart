import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../../../core/theme/scrapyard_theme.dart';

/// Single LaTeX expression (e.g. Smelt final answer).
class LatexDisplay extends StatelessWidget {
  final String latex;
  final Color? color;
  final double fontSize;

  const LatexDisplay({
    super.key,
    required this.latex,
    this.color,
    this.fontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      inherit: false,
      fontSize: fontSize,
      height: 1.2,
      fontWeight: FontWeight.normal,
      color: color ?? ScrapTheme.accent,
      textBaseline: TextBaseline.alphabetic,
    );

    // Mixed answers like "\(a\) or \(b\)" need delimiter parsing — not raw Math.tex.
    final looksMixed = RegExp(r'(\\\(|\\\[|\$\$|\$)').hasMatch(latex) &&
        (latex.contains(r'\)') ||
            latex.contains(r'\]') ||
            latex.split(RegExp(r'\$+|\\\(|\\\[')).length > 2);
    final hasProseBetween = RegExp(
      r'(\\\)|\\\]|\$)\s*[A-Za-z]',
    ).hasMatch(latex);

    if (looksMixed || hasProseBetween) {
      return LatexMarkdownView(
        text: latex,
        baseStyle: style,
      );
    }

    // Single expression: strip wrapping delimiters if present.
    var cleaned = latex.trim();
    if (cleaned.startsWith(r'\(') && cleaned.endsWith(r'\)') && cleaned.length > 4) {
      cleaned = cleaned.substring(2, cleaned.length - 2).trim();
    } else if (cleaned.startsWith(r'\[') &&
        cleaned.endsWith(r'\]') &&
        cleaned.length > 4) {
      cleaned = cleaned.substring(2, cleaned.length - 2).trim();
    } else if (cleaned.startsWith(r'$$') &&
        cleaned.endsWith(r'$$') &&
        cleaned.length > 4) {
      cleaned = cleaned.substring(2, cleaned.length - 2).trim();
    } else if (cleaned.startsWith(r'$') &&
        cleaned.endsWith(r'$') &&
        cleaned.length > 2) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Math.tex(
        cleaned,
        mathStyle: MathStyle.display,
        textStyle: style,
        onErrorFallback: (error) {
          // Fall back to delimiter-aware rendering rather than raw broken latex.
          return LatexMarkdownView(text: latex, baseStyle: style);
        },
      ),
    );
  }
}

/// Renders markdown-ish steps with true inline LaTeX (WidgetSpan)
/// and centered display math. Shared by Smelt popup and AI chat.
class LatexMarkdownView extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;

  /// Tighter line spacing for compact surfaces (e.g. Smelt answer box).
  final bool compact;

  const LatexMarkdownView({
    super.key,
    required this.text,
    this.baseStyle,
    this.compact = false,
  });

  TextStyle get _baseTextStyle {
    final base = baseStyle;
    if (base != null) {
      // Callers may pass an inheriting style; normalize for Text.rich / Math.tex.
      return base.copyWith(
        inherit: false,
        fontSize: base.fontSize ?? 13,
        height: base.height ?? 1.5,
        fontWeight: base.fontWeight ?? FontWeight.normal,
        color: base.color ?? ScrapTheme.bodyText,
        textBaseline: base.textBaseline ?? TextBaseline.alphabetic,
      );
    }
    return TextStyle(
      inherit: false,
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.normal,
      color: ScrapTheme.bodyText,
      fontFamily: ScrapTextStyles.caption.fontFamily,
      textBaseline: TextBaseline.alphabetic,
    );
  }

  TextStyle get _mathOnlyStyle => TextStyle(
        inherit: false,
        fontSize: _baseTextStyle.fontSize ?? 13,
        height: 1.2,
        fontWeight: FontWeight.normal,
        color: _baseTextStyle.color ?? ScrapTheme.bodyText,
        textBaseline: TextBaseline.alphabetic,
      );

  @override
  Widget build(BuildContext context) {
    final lines = _coalesceOrphanBullets(text.split('\n'));

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

    final onlyDisplay = tokens.length == 1 &&
        tokens.single.kind == _TokenKind.displayMath;
    if (onlyDisplay) {
      return _buildDisplayMath(tokens.single.content);
    }

    if (trimmed.startsWith('-') ||
        trimmed.startsWith('*') ||
        trimmed.startsWith('•')) {
      final body = trimmed.substring(1).trimLeft();
      return _buildBulletRow(body);
    }

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
      padding: EdgeInsets.only(bottom: compact ? 0 : 4),
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
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 6),
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
                  textStyle: _mathOnlyStyle,
                  onErrorFallback: (_) => Text(
                    latex,
                    style: _mathOnlyStyle.copyWith(color: ScrapTheme.accent),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

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

  List<_LineToken> _parseLineTokens(String line) {
    final tokens = <_LineToken>[];
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

      final isDisplay = match.group(1) != null || match.group(2) != null;
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
