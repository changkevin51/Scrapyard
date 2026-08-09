import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/ai_engine/domain/latex_json_repair.dart';
import 'package:scrapyard/features/ai_engine/domain/models/smelt_response.dart';

void main() {
  test('repairs \\neg corrupted by JSON \\n escape', () {
    // Simulates jsonDecode of under-escaped "\neg" (newline + "eg").
    const corrupted = 'A \\Rightarrow B \\equiv \neg A \\lor B';
    final repaired = repairLatexCorruptedByJsonEscapes(corrupted);
    expect(repaired, r'A \Rightarrow B \equiv \neg A \lor B');
    expect(repaired.contains('\n'), isFalse);
  });

  test('repairs \\times / \\frac / \\rightarrow corruption', () {
    final corrupted = 'use \times and \frac{1}{2} then \rightarrow';
    final repaired = repairLatexCorruptedByJsonEscapes(corrupted);
    expect(repaired, contains(r'\times'));
    expect(repaired, contains(r'\frac{1}{2}'));
    expect(repaired, contains(r'\rightarrow'));
  });

  test('does not turn newline+"using" into \\nu', () {
    const input = 'Solve.\nusing the formula';
    expect(repairLatexCorruptedByJsonEscapes(input), input);
  });

  test('protectLatexCommandsInRawJson double-escapes \\neg but keeps \\n breaks', () {
    const raw = r'{"steps":"line1\n- A \neg B"}';
    final protected = protectLatexCommandsInRawJson(raw);
    expect(protected, contains(r'\\neg'));
    expect(protected, contains(r'line1\n-'));
    final decoded = jsonDecode(protected) as Map<String, dynamic>;
    expect(decoded['steps'], contains(r'\neg'));
    expect(decoded['steps'], contains('\n'));
  });

  test('SmeltResponse.fromJson repairs answer and steps', () {
    final response = SmeltResponse.fromJson({
      'answer': '\neg A',
      'steps': '- A \\equiv \neg A',
      'isMath': true,
      'suggestions': <String>[],
    }, 'test-model');
    expect(response.answer, r'\neg A');
    expect(response.steps, contains(r'\neg'));
    expect(response.steps.contains('\n'), isFalse);
  });
}
