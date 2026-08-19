import 'dart:math' as math;

/// Result of a successfully parsed simple arithmetic expression.
class ArithmeticResult {
  final String expression;
  final double value;

  const ArithmeticResult({required this.expression, required this.value});

  /// Integer-looking values drop the trailing `.0`.
  /// Otherwise prefer a reduced fraction, except for a lone ratio like `6/2`.
  String get display => _formatAnswer(expression, value, latex: false);

  /// LaTeX form of [display] for the calc popup (`\frac{5}{6}`, `2.5`, `4`).
  String get answerLatex => _formatAnswer(expression, value, latex: true);

  /// True when [display] is a reduced `n/d` rather than a decimal or integer.
  bool get displaysAsFraction => display.contains('/');

  /// Decimal form of [value], for showing beside a fraction in the popup.
  String get decimalDisplay => _decimalString(value);

  String get latex => arithmeticToLatex(expression);
}

/// Pretty-print a solver arithmetic string for the calc popup.
String arithmeticToLatex(String expression) {
  var out = expression;
  var prev = '';
  while (prev != out) {
    prev = out;
    out = out.replaceAllMapped(
      RegExp(r'\(\(([^()]+)\)/\(([^()]+)\)\)'),
      (m) => '\\frac{${m[1]}}{${m[2]}}',
    );
  }
  out = out.replaceAllMapped(
    RegExp(r'sqrt\(([^()]*)\)'),
    (m) => '\\sqrt{${m[1]}}',
  );
  out = out.replaceAll('*', r' \times ');
  out = out.replaceAll('/', r' \div ');
  out = out.replaceAllMapped(
    RegExp(r'\^(\d+(?:\.\d+)?)'),
    (m) => '^{${m[1]}}',
  );
  out = out.replaceAllMapped(
    RegExp(r'\^(\([^)]+\))'),
    (m) => '^{${m[1]}}',
  );
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Turn MathReader LaTeX into a plain arithmetic string, or null if it is not
/// simple arithmetic (`\times`/`\div`/`\cdot`, `\frac`, `\sqrt`, braces, `$`).
String? latexToArithmetic(String latex) {
  var s = correctRecognizedLatex(latex.trim());
  if (s.isEmpty) return null;
  s = s.replaceAll(r'$$', '');
  s = s.replaceAll(r'$', '');
  // Equals and anything to its right are not part of the expression we solve.
  final eqAt = s.indexOf('=');
  if (eqAt >= 0) s = s.substring(0, eqAt).trim();
  if (s.isEmpty) return null;
  s = s.replaceAll(r'\left', '');
  s = s.replaceAll(r'\right', '');
  s = s.replaceAll(r'\cdot', '*');
  s = s.replaceAll(r'\times', '*');
  s = s.replaceAll(r'\div', '/');
  s = s.replaceAll('×', '*');
  s = s.replaceAll('x', '*');
  s = s.replaceAll('X', '*');
  s = s.replaceAll('÷', '/');
  s = s.replaceAll('−', '-');
  s = s.replaceAll('–', '-');
  s = s.replaceAll('—', '-');
  s = s.replaceAll('·', '*');
  s = s.replaceAll(r'\,', '');
  s = s.replaceAll(r'\;', '');
  s = s.replaceAll(r'\!', '');
  s = s.replaceAll('~', '');
  // `^{x}` / `^{*}` is a times glyph stolen as a superscript.
  s = s.replaceAll(r'^{*}', '*');
  s = s.replaceAll(r'^{+}', '*');
  // `\frac{a}{b}c` is multiply; MathReader emits a letter or glued digit, not `\times`.
  s = s.replaceAllMapped(
    RegExp(r'\}(?=\d|\(|sqrt|\\frac|\\sqrt)'),
    (m) => '}*',
  );
  // Innermost fractions first so `\sqrt{\frac{4}{9}}` keeps a complete radicand.
  var prev = '';
  while (prev != s) {
    prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\\frac\{([^{}]*)\}\{([^{}]*)\}'),
      (m) => '((${m[1]})/(${m[2]}))',
    );
  }
  s = s.replaceAllMapped(
    RegExp(r'\\sqrt\s*\[([^\]]*)\]\s*\{([^{}]*)\}'),
    (m) => '((${m[2]})^(1/(${m[1]})))',
  );
  s = s.replaceAllMapped(
    RegExp(r'\\sqrt\s*\{([^{}]*)\}'),
    (m) => 'sqrt(${m[1]})',
  );
  s = s.replaceAll('{', '(');
  s = s.replaceAll('}', ')');
  prev = '';
  while (prev != s) {
    prev = s;
    s = s.replaceAllMapped(
      RegExp(r'\\frac(\([^()]*\))(\([^()]*\))'),
      (m) => '(${m[1]}/${m[2]})',
    );
  }
  s = s.replaceAllMapped(
    RegExp(r'\\sqrt(\([^()]*\))'),
    (m) => 'sqrt${m[1]}',
  );
  s = s.replaceAll(' ', '');
  s = _insertImplicitMul(s);
  if (s.contains(r'\')) return null;
  if (!_isPlainArithmetic(s)) return null;
  return s;
}

/// `(4)3` and `sqrt(4)3` are multiply; `23` stays twenty-three (digits already glued).
String _insertImplicitMul(String s) {
  var prev = '';
  var out = s;
  while (prev != out) {
    prev = out;
    out = out.replaceAllMapped(
      RegExp(r'\)(?=\d|\(|sqrt)'),
      (m) => ')*',
    );
  }
  return out;
}

/// Fix common MathReader confusions in the raw LaTeX (popup + evaluator).
String correctRecognizedLatex(String latex) {
  return latex.replaceAll('z', '2').replaceAll('Z', '2');
}

bool _isPlainArithmetic(String s) {
  return RegExp(r'^(?:sqrt|[0-9+\-*/^().])+$').hasMatch(s);
}

/// Evaluate a restricted arithmetic string. Returns null on any uncertainty.
ArithmeticResult? tryEvaluateArithmetic(String raw) {
  final src = raw.trim();
  if (src.isEmpty) return null;
  if (!_isPlainArithmetic(src)) return null;
  // `--` and `^-` are unary minus; any other consecutive operators are junk.
  final consecutive = src.replaceAll('--', '~').replaceAll('^-', '~');
  if (RegExp(r'[+\-*/^]{2,}').hasMatch(consecutive)) return null;

  try {
    final parser = _Parser(src);
    final value = parser.parseExpression();
    if (!parser.isAtEnd) return null;
    if (value.isNaN || value.isInfinite) return null;
    if (value.abs() > 1e12) return null;
    return ArithmeticResult(expression: src, value: value);
  } catch (_) {
    return null;
  }
}

class _Parser {
  final String src;
  int pos = 0;

  _Parser(this.src);

  bool get isAtEnd => pos >= src.length;

  double parseExpression() {
    var v = parseTerm();
    while (true) {
      _skip();
      if (_eat('+')) {
        v += parseTerm();
      } else if (_matchMinusAsBinary()) {
        pos++;
        v -= parseTerm();
      } else {
        break;
      }
    }
    return v;
  }

  double parseTerm() {
    var v = parsePower();
    while (true) {
      _skip();
      if (_eat('*')) {
        v *= parsePower();
      } else if (_eat('/')) {
        final d = parsePower();
        if (d == 0) throw const FormatException('div0');
        v /= d;
      } else if (_canImplicitMul()) {
        v *= parsePower();
      } else {
        break;
      }
    }
    return v;
  }

  double parsePower() {
    var v = parseUnary();
    _skip();
    if (_eat('^')) {
      final exp = parseUnary();
      v = math.pow(v, exp).toDouble();
    }
    return v;
  }

  double parseUnary() {
    _skip();
    if (_eat('+')) return parseUnary();
    if (_eat('-')) return -parseUnary();
    return parsePrimary();
  }

  double parsePrimary() {
    _skip();
    if (_eatWord('sqrt')) {
      _skip();
      if (!_eat('(')) throw const FormatException('sqrt');
      final v = parseExpression();
      _skip();
      if (!_eat(')')) throw const FormatException('sqrt');
      if (v < 0) throw const FormatException('sqrt');
      return math.sqrt(v);
    }
    if (_eat('(')) {
      final v = parseExpression();
      _skip();
      if (!_eat(')')) throw const FormatException('paren');
      return v;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skip();
    final start = pos;
    while (pos < src.length && _isDigit(src.codeUnitAt(pos))) {
      pos++;
    }
    if (pos < src.length && src[pos] == '.') {
      pos++;
      while (pos < src.length && _isDigit(src.codeUnitAt(pos))) {
        pos++;
      }
    }
    if (start == pos) throw const FormatException('num');
    final n = double.tryParse(src.substring(start, pos));
    if (n == null) throw const FormatException('num');
    return n;
  }

  bool _canImplicitMul() {
    if (isAtEnd) return false;
    if (src.startsWith('sqrt', pos)) return true;
    final c = src[pos];
    return c == '(' || _isDigit(c.codeUnitAt(0));
  }

  bool _matchMinusAsBinary() {
    if (isAtEnd || src[pos] != '-') return false;
    // Binary minus when we already parsed a term; unary is handled in parseUnary.
    return true;
  }

  void _skip() {}

  bool _eat(String ch) {
    if (pos < src.length && src[pos] == ch) {
      pos++;
      return true;
    }
    return false;
  }

  bool _eatWord(String w) {
    if (src.startsWith(w, pos)) {
      pos += w.length;
      return true;
    }
    return false;
  }

  bool _isDigit(int cu) => cu >= 48 && cu <= 57;
}

String _formatAnswer(String expression, double value, {required bool latex}) {
  if (value.isNaN || value.isInfinite) return value.toString();
  if ((value - value.roundToDouble()).abs() < 1e-9 && value.abs() < 1e15) {
    return value.round().toString();
  }
  final decimal = _decimalString(value);
  if (_isSimpleRatio(expression)) return decimal;
  final rat = _rationalFromDouble(value);
  if (rat == null || rat.$2 == 1) return decimal;
  final n = rat.$1;
  final d = rat.$2;
  if (latex) {
    if (n < 0) return '-\\frac{${n.abs()}}{$d}';
    return '\\frac{$n}{$d}';
  }
  return '$n/$d';
}

String _decimalString(double value) {
  var s = value.toStringAsFixed(8);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// True when [src] is a single number divided by a number (or one fraction).
bool _isSimpleRatio(String src) {
  var s = src.replaceAll(' ', '');
  s = _peelWrappingParens(s);
  return RegExp(
    r'^\(?-?\d+(?:\.\d+)?\)?/\(?-?\d+(?:\.\d+)?\)?$',
  ).hasMatch(s);
}

String _peelWrappingParens(String s) {
  while (s.length >= 2 && s.startsWith('(') && s.endsWith(')')) {
    var depth = 0;
    var wraps = true;
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '(') depth++;
      if (s[i] == ')') depth--;
      if (depth == 0 && i != s.length - 1) {
        wraps = false;
        break;
      }
    }
    if (!wraps || depth != 0) break;
    s = s.substring(1, s.length - 1);
  }
  return s;
}

(int, int)? _rationalFromDouble(double value, {int maxDen = 1000}) {
  if (value.isNaN || value.isInfinite) return null;
  final sign = value < 0 ? -1 : 1;
  var x = value.abs();
  var h0 = 0;
  var k0 = 1;
  var h1 = 1;
  var k1 = 0;
  for (var i = 0; i < 24; i++) {
    final a = x.floor();
    final h = a * h1 + h0;
    final k = a * k1 + k0;
    if (k > maxDen) break;
    h0 = h1;
    k0 = k1;
    h1 = h;
    k1 = k;
    if ((value - sign * h1 / k1).abs() < 1e-9 && k1 > 0) {
      return (sign * h1, k1);
    }
    final frac = x - a;
    if (frac.abs() < 1e-12) {
      return (sign * h1, k1);
    }
    x = 1 / frac;
  }
  if (k1 > 0 && (value - sign * h1 / k1).abs() < 1e-9) {
    return (sign * h1, k1);
  }
  return null;
}
