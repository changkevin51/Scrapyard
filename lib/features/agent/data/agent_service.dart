import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/agent_models.dart';
import 'token_repository.dart';

class AgentService {
  final FlutterSecureStorage _storage;
  final TokenRepository _tokenRepo;
  static const String _apiKeyKey = 'openai_api_key';

  AgentService(this._storage, this._tokenRepo);

  Future<Map<String, dynamic>> _callOpenAI(String systemPrompt, String userMessage, {bool jsonMode = false}) async {
    final apiKey = await _storage.read(key: _apiKeyKey);
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey ?? 'dummy_key'}',
      },
      body: jsonEncode({
        'model': 'gpt-4o-mini',
        if (jsonMode) 'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage}
        ],
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['choices'][0]['message']['content'];
      final usage = data['usage']['total_tokens'] as int? ?? 0;
      await _tokenRepo.logTokens(usage);
      return {'content': content, 'usage': usage};
    } else {
      throw Exception('OpenAI API Error: ${response.statusCode}');
    }
  }

  Future<RestructureResult> restructureText(String original) async {
    const prompt = 'Improve the flow, clarity, and grammatical correctness of this text. Return JSON with exactly: {"proposed": "new text"}';
    final res = await _callOpenAI(prompt, original, jsonMode: true);
    final mapped = jsonDecode(res['content']);
    return RestructureResult(original: original, proposed: mapped['proposed']);
  }

  Future<StudyPlan> createStudyPlan(String topic) async {
     const prompt = 'Create a study plan for this topic. Return JSON schema: {"title": "...", "estimated_hours": 10, "topics": [{"name": "...", "description": "...", "resources": ["...", "..."]}]}';
     final res = await _callOpenAI(prompt, topic, jsonMode: true);
     final mapped = jsonDecode(res['content']);
     final topics = (mapped['topics'] as List).map((t) => StudyTopic(
       name: t['name'],
       description: t['description'],
       resources: List<String>.from(t['resources'] ?? [])
     )).toList();
     return StudyPlan(title: mapped['title'], estimatedHours: mapped['estimated_hours'], topics: topics);
  }

  Future<String> searchAndSummarize(String query) async {
    final ddgUrl = Uri.parse('https://api.duckduckgo.com/?q=${Uri.encodeComponent(query)}&format=json');
    final ddgRes = await http.get(ddgUrl);
    String context = '';
    if (ddgRes.statusCode == 200) {
      final ddgData = jsonDecode(ddgRes.body);
      context = ddgData['AbstractText'] ?? ddgData['RelatedTopics']?.toString() ?? '';
    }
    
    const prompt = 'Summarize the given search facts to directly answer the query. If no facts exist, answer from your knowledge concisely.';
    final openAiUser = 'Query: $query\\nFacts: $context';
    final res = await _callOpenAI(prompt, openAiUser);
    return res['content'];
  }

  Future<String> summarizePdf(String fullText) async {
     const chunkSize = 10000;
     const overlap = 800; 
     List<String> chunkSummaries = [];

     for (int i = 0; i < fullText.length; i += (chunkSize - overlap)) {
         final end = (i + chunkSize < fullText.length) ? i + chunkSize : fullText.length;
         final chunk = fullText.substring(i, end);
         
         const prompt = 'Summarize this section of the document.';
         final res = await _callOpenAI(prompt, chunk);
         chunkSummaries.add(res['content']);
         if (end == fullText.length) break;
     }

     const finalPrompt = '''
Synthesize these section summaries into a single comprehensive overview containing:
- Main argument
- Key claims
- Methodology
- Critical questions
- Key terms
''';
     final res2 = await _callOpenAI(finalPrompt, chunkSummaries.join('\\n---VERBOSE---\\n'));
     return res2['content'];
  }

  Future<String> askAnything(String query, String contextStr) async {
    const prompt = 'You are a thoughtful study assistant. Answer the user based on the context if applicable.';
    final msg = 'Context: $contextStr\\n\\nUser: $query';
    final res = await _callOpenAI(prompt, msg);
    return res['content'];
  }
}
