import '../models/stroke.dart';
import 'ink_geometry.dart';
import 'simple_arithmetic.dart';

/// Turn an ML Kit candidate plus stroke geometry into a strict arithmetic
/// string, or null when anything looks uncertain.
String? normalizeMathInk({
  required String recognized,
  required List<Stroke> expressionStrokes,
}) {
  if (looksLikeStackedFraction(expressionStrokes)) return null;

  var text = recognized.trim();
  if (text.isEmpty) return null;

  text = text.replaceAll('÷', '/');
  text = text.replaceAll('−', '-');
  text = text.replaceAll('–', '-');
  text = text.replaceAll('—', '-');
  text = text.replaceAll('∗', '*');
  text = text.replaceAll('×', 'x');
  text = text.replaceAll('·', 'x');
  text = text.replaceAll(' ', '');
  text = text.replaceAll(',', '');
  if (text.endsWith('=')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) return null;

  final multiplied = _xAsMultiply(text);
  if (multiplied == null) return null;
  text = multiplied;

  text = _patchOperatorsFromGeometry(text, expressionStrokes);

  // Only treat raised glyphs as exponents when the candidate is all digits
  // (e.g. "32" → "3^2"). A minus on the midline is not an exponent.
  if (RegExp(r'^[0-9.]+$').hasMatch(text)) {
    final glyphs = groupGlyphs(expressionStrokes);
    final supers = superscriptGlyphIndexes(glyphs);
    if (supers.isNotEmpty) {
      final inserted = _insertCarets(text, glyphs.length, supers);
      if (inserted == null) return null;
      text = inserted;
    }
  }

  if (!RegExp(r'^[0-9+\-*/^().]+$').hasMatch(text)) return null;
  return text;
}

/// Prefer geometric `+` over ML Kit's habitual minus.
String _patchOperatorsFromGeometry(String text, List<Stroke> strokes) {
  final ops = detectArithmeticOperators(strokes);
  if (ops.isEmpty) return text;
  final plusCount = ops.where((o) => o.symbol == '+').length;
  if (plusCount == 0) return text;

  var minusSeen = 0;
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '-' && minusSeen < plusCount) {
      buf.write('+');
      minusSeen++;
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

/// First candidate that is a plain number (operand recognition).
String? firstNumericToken(
  Iterable<String> candidates, {
  List<Stroke> strokes = const [],
}) {
  for (final raw in candidates) {
    var t = raw.trim().replaceAll(' ', '').replaceAll(',', '');
    t = t.replaceAll('−', '-').replaceAll('–', '-').replaceAll('—', '-');
    if (RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(t)) return t;
    if (t == 'l' || t == 'I' || t == '|' || t == 'i') return '1';
    if (t == 'O' || t == 'o' || t == 'D') return '0';
    if (t == 'Z') return '2';
    if (t == 'S') return '5';
  }
  if (strokes.length == 1 && isVerticalBar(strokes.first, minHeight: 8)) {
    return '1';
  }
  return null;
}

/// Try candidates until one normalizes and evaluates.
ArithmeticResult? firstSolvableCandidate({
  required Iterable<String> candidates,
  required List<Stroke> expressionStrokes,
}) {
  for (final raw in candidates) {
    final normalized = normalizeMathInk(
      recognized: raw,
      expressionStrokes: expressionStrokes,
    );
    if (normalized == null) continue;
    final result = tryEvaluateArithmetic(normalized);
    if (result != null) return result;
  }
  return null;
}

String? _xAsMultiply(String text) {
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == 'x' || c == 'X') {
      final prev = i > 0 ? text[i - 1] : '';
      final next = i + 1 < text.length ? text[i + 1] : '';
      final leftNum = _isDigitOrClose(prev);
      final rightNum = _isDigitOrOpen(next);
      if (leftNum && rightNum) {
        buf.write('*');
      } else {
        return null;
      }
    } else {
      buf.write(c);
    }
  }
  final out = buf.toString();
  if (RegExp(r'[A-Za-z]').hasMatch(out)) return null;
  return out;
}

bool _isDigitOrClose(String c) =>
    c.isNotEmpty && (RegExp(r'[0-9)]').hasMatch(c));

bool _isDigitOrOpen(String c) =>
    c.isNotEmpty && (RegExp(r'[0-9(]').hasMatch(c));

String? _insertCarets(String text, int glyphCount, Set<int> supers) {
  // Only the characters that correspond 1:1 with glyphs.
  final chars = text.split('');
  if (chars.length != glyphCount) return null;
  final buf = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    if (supers.contains(i)) {
      if (i == 0) return null;
      buf.write('^');
    }
    buf.write(chars[i]);
  }
  return buf.toString();
}
