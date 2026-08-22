import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../ai_engine/data/smelt_service.dart';
import '../../ai_engine/data/gemini_api.dart';
import '../domain/models/chat_message.dart';
import '../domain/models/gemini_model.dart';

/// Result of a completed chat stream (visible text + parsed suggestions).
class ChatStreamResult {
  final String text;
  final List<String> suggestions;
  final String modelUsed;
  final String? requestedModel;
  final String? fallbackReason;

  const ChatStreamResult({
    required this.text,
    required this.suggestions,
    required this.modelUsed,
    this.requestedModel,
    this.fallbackReason,
  });

  bool get didFallback =>
      requestedModel != null &&
      fallbackReason != null &&
      requestedModel != modelUsed;
}

/// Multi-turn Gemini chat with SSE streaming and suggestion sentinel parsing.
class GeminiChatService {
  final FlutterSecureStorage _storage;

  static const String _suggestionsMarker = '<<SUGGESTIONS>>';

  static const String systemPrompt = '''
You are Scrapyard's Ask — a helpful voice inside a digital scrap-paper notebook.

Style:
- Be concise and clear. Prefer short paragraphs and bullet lists.
- Use markdown when it helps (lists, bold, headings sparingly).
- For math, use these EXACT LaTeX delimiters:
  * Inline: \\( ... \\)
  * Display: \\[ ... \\]
  Prefer inline math inside sentences. Never write ascii math like "x^2/4".

After your full answer, ALWAYS end with exactly one line in this format (no extra text after it):
$_suggestionsMarker Short question 1|Short question 2|Short question 3

Rules for that line:
- Exactly 2 or 3 short follow-up questions a student might ask next
- Each question max 5–6 words
- Pipe-separated, no quotes
- Examples: Explain in more detail|Why the chain rule?|Show another example
''';

  GeminiChatService(this._storage);

  Future<String> _requireApiKey() async {
    final stored = await _storage.read(key: SmeltService.apiKeyStorageKey);
    final apiKey = stored?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(SmeltService.missingApiKeyMessage);
    }
    return apiKey;
  }

  /// Stream a reply. Yields visible text deltas (suggestions stripped).
  /// Completes with the full [ChatStreamResult] via the returned Future's
  /// companion — callers should listen to the stream and await [onDone].
  Stream<String> streamChat({
    required List<ChatMessage> history,
    required String preferredModel,
    Uint8List? imageBytes,
    void Function(ChatStreamResult result)? onComplete,
  }) async* {
    final apiKey = await _requireApiKey();

    final models = GeminiChatModel.fallbackChain(preferredModel);
    Object? lastError;
    String? lastRetryReason;

    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        ChatStreamResult? completed;
        yield* _streamOnce(
          apiKey: apiKey,
          model: model,
          history: history,
          imageBytes: imageBytes,
          onComplete: (result) => completed = result,
        );
        if (completed != null) {
          final result = i > 0 && lastRetryReason != null
              ? ChatStreamResult(
                  text: completed!.text,
                  suggestions: completed!.suggestions,
                  modelUsed: completed!.modelUsed,
                  requestedModel: preferredModel,
                  fallbackReason: lastRetryReason,
                )
              : completed!;
          onComplete?.call(result);
        }
        return;
      } catch (e) {
        lastError = e;
        if (!GeminiChatModel.isRetryableError(e) || i == models.length - 1) {
          rethrow;
        }
        lastRetryReason = GeminiChatModel.describeFallbackReason(e);
      }
    }

    throw Exception('All Gemini models failed: $lastError');
  }

  Stream<String> _streamOnce({
    required String apiKey,
    required String model,
    required List<ChatMessage> history,
    Uint8List? imageBytes,
    void Function(ChatStreamResult result)? onComplete,
  }) async* {
    final url = GeminiApi.streamGenerateContent(model);

    final contents = <Map<String, dynamic>>[];
    for (var i = 0; i < history.length; i++) {
      final msg = history[i];
      final parts = <Map<String, dynamic>>[];

      // Prefer the image stored on the message itself (persisted attachments).
      final msgImage = msg.image;
      if (msg.role == ChatRole.user &&
          msgImage != null &&
          msgImage.isNotEmpty) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/png',
            'data': base64Encode(msgImage),
          },
        });
      } else if (i == 0 &&
          msg.role == ChatRole.user &&
          imageBytes != null &&
          imageBytes.isNotEmpty) {
        // Smelt-seed fallback: one-shot image on the first user turn.
        parts.add({
          'inline_data': {
            'mime_type': 'image/png',
            'data': base64Encode(imageBytes),
          },
        });
      }
      parts.add({'text': msg.content});

      contents.add({
        'role': msg.role == ChatRole.user ? 'user' : 'model',
        'parts': parts,
      });
    }

    final requestBody = {
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 2048,
      },
    };

    final request = http.Request('POST', url)
      ..headers.addAll(GeminiApi.headers(apiKey))
      ..body = jsonEncode(requestBody);

    final streamed = await request.send().timeout(const Duration(seconds: 60));

    if (streamed.statusCode == 429) {
      throw Exception('Rate limit exceeded (429)');
    }
    if (streamed.statusCode != 200) {
      throw Exception('Gemini API error: ${streamed.statusCode}');
    }

    final buffer = StringBuffer(); // raw accumulated (incl. sentinel)
    var visibleEmitted = 0; // how much visible text we've yielded
    var lineBuf = '';

    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      lineBuf += chunk;
      while (true) {
        final nl = lineBuf.indexOf('\n');
        if (nl < 0) break;
        final line = lineBuf.substring(0, nl).trimRight();
        lineBuf = lineBuf.substring(nl + 1);

        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;

        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates == null || candidates.isEmpty) continue;
          final content = candidates[0]['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts == null || parts.isEmpty) continue;
          final text = parts[0]['text'] as String?;
          if (text == null || text.isEmpty) continue;

          buffer.write(text);
          final visible = _visiblePrefix(buffer.toString());
          if (visible.length > visibleEmitted) {
            final delta = visible.substring(visibleEmitted);
            visibleEmitted = visible.length;
            yield delta;
          }
        } catch (_) {
          // skip malformed SSE frames
        }
      }
    }

    // Flush any remaining line
    if (lineBuf.trim().isNotEmpty && lineBuf.trim().startsWith('data:')) {
      final payload = lineBuf.trim().substring(5).trim();
      if (payload.isNotEmpty && payload != '[DONE]') {
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            final text = parts?.isNotEmpty == true
                ? parts![0]['text'] as String?
                : null;
            if (text != null && text.isNotEmpty) {
              buffer.write(text);
            }
          }
        } catch (_) {}
      }
    }

    final raw = buffer.toString();
    final parsed = _parseSuggestions(raw);
    final finalVisible = parsed.text;
    if (finalVisible.length > visibleEmitted) {
      yield finalVisible.substring(visibleEmitted);
    }

    onComplete?.call(ChatStreamResult(
      text: finalVisible,
      suggestions: parsed.suggestions,
      modelUsed: model,
    ));
  }

  /// Returns the portion of [raw] that is safe to show (before sentinel).
  /// While the sentinel is incomplete (starts with `<` near the end),
  /// hold back the ambiguous tail so it never flashes on screen.
  static String _visiblePrefix(String raw) {
    final idx = raw.indexOf(_suggestionsMarker);
    if (idx >= 0) {
      return raw.substring(0, idx).trimRight();
    }
    // Hold back a short tail if it might be the start of the marker.
    const hold = 16; // <<SUGGESTIONS>> length
    if (raw.length <= hold) {
      // If the whole buffer could be a prefix of the marker, hold it.
      if (_suggestionsMarker.startsWith(raw.trimLeft()) ||
          raw.contains('<<')) {
        final angle = raw.lastIndexOf('<<');
        if (angle >= 0) return raw.substring(0, angle).trimRight();
      }
      return raw;
    }
    const holdBack = 16; // length of <<SUGGESTIONS>>
    final tail = raw.substring(raw.length - holdBack);
    if (tail.contains('<<')) {
      final angle = raw.lastIndexOf('<<');
      if (angle >= 0 &&
          _suggestionsMarker.startsWith(raw.substring(angle))) {
        return raw.substring(0, angle).trimRight();
      }
    }
    return raw;
  }

  static ({String text, List<String> suggestions}) _parseSuggestions(
    String raw,
  ) {
    final idx = raw.indexOf(_suggestionsMarker);
    if (idx < 0) {
      return (text: raw.trimRight(), suggestions: const <String>[]);
    }
    final text = raw.substring(0, idx).trimRight();
    final after = raw.substring(idx + _suggestionsMarker.length).trim();
    // Take only the first line after the marker
    final line = after.split('\n').first.trim();
    final suggestions = line
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    return (text: text, suggestions: suggestions);
  }
}
