/// Repairs LaTeX broken when JSON treats the start of a TeX command as an escape.
///
/// Gemini often emits single-backslash TeX inside JSON strings (e.g. `\neg`).
/// In JSON, `\n` / `\t` / `\r` / `\b` / `\f` are real escapes, so `\neg` becomes
/// a newline + `eg`. That also splits `\(...\)` across lines and leaves raw
/// delimiters visible in the Smelt UI.

/// Control characters produced by JSON single-letter escapes.
const _jsonEscapeControls = [0x08, 0x09, 0x0A, 0x0C, 0x0D]; // \b \t \n \f \r

/// Suffixes after the eaten escape letter, keyed by that letter.
///
/// Example: `\neg` → JSON eats `\n` → control 0x0A + suffix `eg`.
/// Longer suffixes must come first so `\rightarrow` wins over `\right`.
const _suffixesByEscapeLetter = <String, List<String>>{
  'n': [
    'Leftrightarrow',
    'Rightarrow',
    'leftarrow',
    'rightarrow',
    'subseteq',
    'supseteq',
    'parallel',
    'approx',
    'exists',
    'atural',
    'less',
    'gtr',
    'leq',
    'geq',
    'mid',
    'sim',
    'cong',
    'otin',
    'abla',
    'eg',
    'eq',
    'i',
    'u',
  ],
  't': [
    'woheadrightarrow',
    'extbf',
    'extit',
    'extrm',
    'exttt',
    'extsf',
    'riangleq',
    'riangle',
    'imes',
    'heta',
    'anh',
    'ext',
    'au',
    'an',
    'ilde',
    'frac',
    'binom',
    'op',
    'o',
  ],
  'r': [
    'ightleftharpoons',
    'ightharpoonup',
    'ightharpoondown',
    'ightarrowtail',
    'ightarrow',
    'angle',
    'floor',
    'ceil',
    'ight',
    'vert',
    'Vert',
    'ho',
  ],
  'b': [
    'igcup',
    'igcap',
    'igvee',
    'igwedge',
    'igodot',
    'igoplus',
    'igotimes',
    'oldsymbol',
    'inom',
    'egin',
    'bmath',
    'fmath',
    'igg',
    'igl',
    'igr',
    'igL',
    'igR',
    'eta',
    'ar',
    'ot',
    'ig',
  ],
  'f': [
    'orall',
    'loor',
    'rac',
    'rown',
    'box',
    'lat',
  ],
};

/// TeX command names (without leading `\`) that start with a JSON escape letter.
/// Used to pre-escape raw LaTeX inside broken JSON before [jsonDecode].
List<String> get latexCommandsStartingWithJsonEscape {
  final names = <String>[];
  _suffixesByEscapeLetter.forEach((letter, suffixes) {
    for (final suffix in suffixes) {
      names.add('$letter$suffix');
    }
  });
  names.sort((a, b) => b.length.compareTo(a.length));
  return names;
}

/// Restore TeX commands corrupted by JSON escape decoding in answer/steps text.
String repairLatexCorruptedByJsonEscapes(String input) {
  if (input.isEmpty) return input;
  if (!input.codeUnits.any(_jsonEscapeControls.contains)) return input;

  var result = input;
  _suffixesByEscapeLetter.forEach((letter, suffixes) {
    final control = _controlForEscapeLetter(letter);
    final ordered = [...suffixes]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final suffix in ordered) {
      final broken = String.fromCharCode(control) + suffix;
      // Avoid eating the start of ordinary words ("\nusing" must not become "\nu").
      result = result.replaceAllMapped(
        RegExp('${RegExp.escape(broken)}(?![a-zA-Z])'),
        (_) => '\\$letter$suffix',
      );
    }
  });
  return result;
}

/// In raw JSON text, turn `\neg` into `\\neg` (etc.) so [jsonDecode] keeps TeX
/// intact, while leaving real `\n` line-break escapes alone.
String protectLatexCommandsInRawJson(String json) {
  final names = latexCommandsStartingWithJsonEscape;
  if (names.isEmpty) return json;
  final alternation = names.map(RegExp.escape).join('|');
  // Single backslash + command name, not already escaped.
  return json.replaceAllMapped(
    RegExp('(?<![\\\\])\\\\($alternation)(?![a-zA-Z])'),
    (match) => '\\\\${match.group(1)}',
  );
}

int _controlForEscapeLetter(String letter) {
  switch (letter) {
    case 'b':
      return 0x08;
    case 't':
      return 0x09;
    case 'n':
      return 0x0A;
    case 'f':
      return 0x0C;
    case 'r':
      return 0x0D;
    default:
      throw ArgumentError('Not a JSON escape letter: $letter');
  }
}
