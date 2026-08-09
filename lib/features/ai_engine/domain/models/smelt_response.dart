import '../latex_json_repair.dart';

/// One code-execution turn from Gemini (source + optional stdout).
class SmeltCodeRun {
  final String language;
  final String code;
  final String output;

  const SmeltCodeRun({
    required this.language,
    required this.code,
    this.output = '',
  });
}

/// Response model for the Smelt AI feature
class SmeltResponse {
  /// The direct answer (for math questions, this is the final answer).
  /// Empty when the solution has no single concise result (e.g. proofs).
  final String answer;

  /// Step-by-step solution in markdown with LaTeX support
  /// Empty string if no steps are needed
  final String steps;

  /// Whether a punchline answer should be shown in the answer box.
  bool get hasDirectAnswer => answer.trim().isNotEmpty;

  /// Whether this is a math question
  final bool isMath;

  /// The model that was used to generate this response
  final String modelUsed;

  /// Set when a tiered fallback picked a different model than requested.
  final String? modelFallbackNote;

  /// Short follow-up questions (2–3) for continuing in chat
  final List<String> suggestions;

  /// Code execution runs captured from Gemini tool parts.
  final List<SmeltCodeRun> codeRuns;

  const SmeltResponse({
    required this.answer,
    required this.steps,
    required this.isMath,
    required this.modelUsed,
    this.modelFallbackNote,
    this.suggestions = const [],
    this.codeRuns = const [],
  });

  bool get usedCodeExecution => codeRuns.isNotEmpty;

  factory SmeltResponse.fromJson(
    Map<String, dynamic> json,
    String modelUsed, {
    List<SmeltCodeRun> codeRuns = const [],
  }) {
    List<String> suggestions = const [];
    final raw = json['suggestions'];
    if (raw is List) {
      suggestions = raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList();
    }
    return SmeltResponse(
      answer: repairLatexCorruptedByJsonEscapes(
        json['answer'] as String? ?? '',
      ),
      steps: repairLatexCorruptedByJsonEscapes(
        json['steps'] as String? ?? '',
      ),
      isMath: json['isMath'] as bool? ?? false,
      modelUsed: modelUsed,
      suggestions: suggestions,
      codeRuns: codeRuns,
    );
  }
}
