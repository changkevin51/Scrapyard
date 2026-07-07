/// Response model for the Smelt AI feature
class SmeltResponse {
  /// The direct answer (for math questions, this is the final answer)
  final String answer;
  
  /// Step-by-step solution in markdown with LaTeX support
  /// Empty string if no steps are needed
  final String steps;
  
  /// Whether this is a math question
  final bool isMath;
  
  /// The model that was used to generate this response
  final String modelUsed;

  const SmeltResponse({
    required this.answer,
    required this.steps,
    required this.isMath,
    required this.modelUsed,
  });

  factory SmeltResponse.fromJson(Map<String, dynamic> json, String modelUsed) {
    return SmeltResponse(
      answer: json['answer'] as String? ?? '',
      steps: json['steps'] as String? ?? '',
      isMath: json['isMath'] as bool? ?? false,
      modelUsed: modelUsed,
    );
  }
}