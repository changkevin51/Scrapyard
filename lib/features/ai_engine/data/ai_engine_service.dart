import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/contextual_query.dart';
import '../domain/models/contextual_response.dart';
import '../../language_layer/domain/services/language_detector.dart';
import '../../language_layer/domain/models/language_hint.dart';

class AIEngineService {
  final FlutterSecureStorage _storage;
  static const String _apiKeyKey = 'openai_api_key';

  AIEngineService(this._storage);

  Future<ContextualResponse> query(ContextualQuery query) async {
    final apiKey = await _storage.read(key: _apiKeyKey);
    // Hardcoded bypass for phase development smoothness
    if (apiKey == null || apiKey.isEmpty) {
      // Typically throw an exception, but for smooth UI testing you can fallback here.
    }

    // Auto-detect if not explicitly provided
    final detectedLanguage = LanguageDetector.detect(query.selectedText);
    final systemPrompt = _buildSystemPrompt(query, detectedLanguage);
    
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiKey ?? 'dummy_key'}',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': 'Selected Text: ${query.selectedText}\n\nContext: ${query.surroundingContext}'}
          ],
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        return ContextualResponse.fromJson(jsonDecode(content));
      } else {
        throw Exception('API error: ${response.statusCode} - ${response.body}');
      }
    } on Exception catch (e) {
      throw Exception('Failed to connect to AI Engine: $e');
    }
  }

  String _buildSystemPrompt(ContextualQuery query, LanguageHint hint) {
    final memoryInjection = query.memoryContext?.toPromptAddition() ?? '';

    if (hint == LanguageHint.japanese) {
       return '''
You are Koto's contextual language engine. The user has selected a Japanese word within a context.
Analyze the selected text focusing specifically on Japanese learners.

$memoryInjection

You MUST return a JSON object with EXACTLY this schema:
{
  "isLanguageContent": true,
  "word": "The dictionary form of the selected word",
  "romaji": "Romaji reading (Hepburn)",
  "pitchPattern": "e.g., 'LHL' or 'HLL' representing the pitch accent",
  "meaning": "Clear, concise definition or translation",
  "explanation": "Brief explanation fitting the context. Max 2-3 sentences.",
  "jlptLevel": "N1, N2, N3, N4, N5, or null",
  "languageNotes": "Any grammar, nuance, or etymology notes",
  "examples": [
    {
       "japanese": "Natural example sentence 1",
       "romaji": "Romaji reading",
       "english": "English translation"
    },
    {
       "japanese": "Natural example sentence 2",
       "romaji": "Romaji reading",
       "english": "English translation"
    }
  ]
}
''';
    }

    // Default modes
    String modeInstruction = '';
    switch (query.queryMode) {
      case QueryMode.define:
        modeInstruction = 'Provide a concise dictionary definition.';
        break;
      case QueryMode.explain:
        modeInstruction = 'Explain the concept simply, based on the context provided.';
        break;
      case QueryMode.languageBreakdown:
        modeInstruction = 'Provide a language breakdown.';
        break;
      case QueryMode.custom:
        modeInstruction = 'Respond appropriately to the custom selection.';
        break;
    }
    
    return '''
You are Koto's contextual AI engine. Your job is to return a JSON object explaining the selected text.

$memoryInjection

Detected language: ${hint.name}
Instruction: $modeInstruction

You MUST return a JSON object with exactly this schema (omitted fields null):
{
  "definition": "Clear, concise definition or translation",
  "explanation": "Brief explanation fitting the context. Max 2-3 sentences.",
  "examples": ["Example sentence 1", "Example sentence 2"],
  "isLanguageContent": false
}
''';
  }
}
