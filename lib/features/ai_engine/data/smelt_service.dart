import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/smelt_response.dart';
import '../_debug_log_helper.dart';

/// Callback for streaming progress updates
typedef SmeltProgressCallback = void Function({
  String? partialAnswer,
  String? partialSteps,
  bool isComplete,
  String? error,
});

/// Result from a streaming smelt operation
class SmeltStreamResult {
  final SmeltResponse response;
  final String modelUsed;

  const SmeltStreamResult({required this.response, required this.modelUsed});
}

/// Service for the Smelt AI feature using Gemini API with fallback chain
class SmeltService {
  final FlutterSecureStorage _storage;

  /// Shared storage key used by [ApiKeyService] and Smelt.
  static const String apiKeyStorageKey = 'gemini_api_key';

  /// User-facing message when no API key is configured.
  static const String missingApiKeyMessage =
      'No Gemini API key set. Open Settings > Gemini API Key to add your free key.';

  // Gemini models in priority order (fallback chain)
  static const List<String> _models = [
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
    'gemini-3.5-flash-lite'
    'gemini-3.1-flash-lite',
  ];

  /// Cheapest model in the fallback chain — used for API key testing.
  static String get cheapestModel => _models.last;

  SmeltService(this._storage);

  /// Analyze the selected region image and return AI response
  Future<SmeltResponse> analyzeSelection(Uint8List? imageBytes) async {
    final result = await analyzeSelectionStream(imageBytes);
    return result.response;
  }

  /// Analyze with streaming support for faster perceived response time
  Future<SmeltStreamResult> analyzeSelectionStream(
    Uint8List? imageBytes, {
    SmeltProgressCallback? onProgress,
  }) async {
    final storedKey = await _storage.read(key: apiKeyStorageKey);
    final apiKey = storedKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(missingApiKeyMessage);
    }

    String? base64Image;
    if (imageBytes != null) {
      final compressedImage = await compute(_compressImageWorker, imageBytes);
      base64Image = base64Encode(compressedImage);
    }

    // Try each model in order until one succeeds
    for (final model in _models) {
      try {
        final response = await _callGemini(apiKey, model, base64Image, onProgress);
        return response;
      } catch (e) {
        if (e.toString().contains('429') || 
            e.toString().contains('RESOURCE_EXHAUSTED') ||
            e.toString().contains('rate') ||
            e.toString().contains('quota')) {
          continue;
        }
        if (model == _models.last) {
          throw Exception('All Gemini models failed: $e');
        }
      }
    }

    throw Exception('All Gemini models are unavailable');
  }

  Future<SmeltStreamResult> _callGemini(
    String apiKey, 
    String model, 
    String? base64Image,
    SmeltProgressCallback? onProgress,
  ) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

    const systemPrompt = '''
You are Scrapyard's AI smelt engine. Analyze the handwritten content in the image.

IMPORTANT RULES:
1. If this is a MATH question/problem:
   - Put ONLY the final answer in the "answer" field as LaTeX using \\( ... \\)
     (e.g., "\\(x = 5\\)", "\\(42\\)", "\\(\\frac{\\pi}{2}\\)", "\\(\\frac{x^4}{4} + x^2 + 5x + C\\)")
   - Put the step-by-step solution in the "steps" field
   - Set "isMath" to true

2. If this is NOT a math question:
   - Put the main answer/explanation in the "answer" field
   - Put any additional details or explanation steps in the "steps" field (can be empty if answer is complete)
   - Set "isMath" to false

3. For the "steps" field (when needed):
   - Use markdown formatting
   - DO NOT use LaTeX for a single bare variable/letter alone in a sentence. Write those as plain text
     (e.g., "solve for x", "coefficient of y").
   - DO use inline LaTeX for ANY non-trivial math so it can stay on the same line as the sentence:
     exponents, fractions, roots, integrals, sums, products, multi-term expressions, or equations.
     Examples: \\(x^2\\), \\(\\frac{x^4}{4}\\), \\(2x + 5\\), \\(\\int x^2\\,dx\\)
     NEVER write these as ascii/plain text like "x^4/4" or "x^(n+1)".
   - For LaTeX math, use these EXACT delimiters:
     * Inline math (preferred): \\( ... \\)  — stays in the sentence
     * Display math (rare): \\[ ... \\]  — ONLY for a final standalone result equation on its own line
       (e.g., \\[\\frac{x^4}{4} + x^2 + 5x + C\\])
   - Prefer inline \\( ... \\) over display math whenever the expression appears inside a sentence or bullet.
   - CRITICAL: Bullet/list items that are ONLY an equation must put the math on the SAME line as the bullet.
     Correct: "- \\(\\int x^3\\,dx = \\frac{x^4}{4}\\)"
     Wrong: a bullet alone on one line and the equation on the next line.
   - Use bullet points or numbered lists
   - Keep steps EXTREMELY CONCISE - 1-2 lines maximum per step.
   - NEVER put sentence punctuation (like periods or commas) on a new line after a latex expression. Omit trailing punctuation for display math entirely.

4. Be concise and clear. The answer should be immediately useful to a student.

You MUST respond with ONLY a JSON object in this exact format:
{
  "answer": "The direct answer here",
  "steps": "Step-by-step in markdown with LaTeX (or empty string if not needed)",
  "isMath": true or false
}
''';

    final parts = <Map<String, dynamic>>[
      {'text': systemPrompt},
    ];
    
    if (base64Image != null) {
      parts.add({
        'inline_data': {
          'mime_type': 'image/png',
          'data': base64Image,
        },
      });
      parts.add({'text': 'Analyze this handwritten content and provide the answer.'});
    } else {
      parts.add({'text': 'No image available. Please respond that the image could not be captured.'});
    }

    final requestBody = {
      'contents': [
        {
          'parts': parts,
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 1024,
        'responseMimeType': 'application/json',
      },
    };

    // Send request and stream the response body chunks
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(requestBody);

    final stream = request.send().timeout(const Duration(seconds: 30));
    final response = await stream;

    if (response.statusCode == 200) {
      // Accumulate the response body as chunks arrive
      final accumulated = StringBuffer();
      await for (final chunk in response.stream) {
        accumulated.write(String.fromCharCodes(chunk));
      }

      // Parse the complete response
      final responseBody = accumulated.toString();
      final data = jsonDecode(responseBody);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('No response from Gemini');
      }

      final content = candidates[0]['content']['parts'][0]['text'] as String;

      // #region agent log
      dlog('H1_H4_raw_content', 'raw content from gemini before any parsing',
          {'model': model, 'contentJsonEncoded': jsonEncode(content)});
      // #endregion

      try {
        final jsonResponse = await compute(_parseJsonWorker, content);

        // #region agent log
        dlog(
            'H1_H2_direct_parse_steps',
            'steps field right after DIRECT jsonDecode succeeded (no repair needed)',
            {
              'model': model,
              'stepsJsonEncoded': jsonEncode(jsonResponse['steps']),
            });
        // #endregion

        onProgress?.call(
          partialAnswer: jsonResponse['answer'] as String?,
          partialSteps: jsonResponse['steps'] as String?,
          isComplete: true,
        );

        final responseModel = SmeltResponse.fromJson(jsonResponse, model);
        return SmeltStreamResult(
          response: responseModel,
          modelUsed: model,
        );
      } on FormatException catch (e) {
        print('=== GEMINI JSON PARSE ERROR ===');
        print('Error: $e');
        print('Raw content from Gemini:');
        print(content);
        print('=== END GEMINI RESPONSE ===');

        try {
          final fixedAndParsed = await compute(_fixAndParseJsonWorker, content);
          final jsonResponse = fixedAndParsed;

          // #region agent log
          dlog(
              'H1_H2_repaired_parse_steps',
              'steps field right after FALLBACK repair+parse succeeded',
              {
                'model': model,
                'stepsJsonEncoded': jsonEncode(jsonResponse['steps']),
              });
          // #endregion

          onProgress?.call(
            partialAnswer: jsonResponse['answer'] as String?,
            partialSteps: jsonResponse['steps'] as String?,
            isComplete: true,
          );

          final responseModel = SmeltResponse.fromJson(jsonResponse, model);
          return SmeltStreamResult(
            response: responseModel,
            modelUsed: model,
          );
        } catch (e2) {
          print('=== SECOND PARSE ERROR ===');
          print('Error: $e2');
          print('=== END SECOND PARSE ERROR ===');
          throw Exception('Failed to parse Gemini response: $e2\nRaw response: $content');
        }
      }
    } else if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded (429)');
    } else {
      throw Exception('Gemini API error: ${response.statusCode} - ${await response.stream.bytesToString()}');
    }
  }

  /// Worker function for JSON parsing in isolate
  static Map<String, dynamic> _parseJsonWorker(String content) {
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Worker function for fixing and parsing JSON in isolate
  static Map<String, dynamic> _fixAndParseJsonWorker(String content) {
    final fixed = _fixJsonEscapeSequences(content);

    // #region agent log
    dlog(
        'H1_escape_fix_before_after',
        'comparing raw content vs escape-fixed content around \\b \\f \\n \\r \\t sequences',
        {
          'beforeJsonEncoded': jsonEncode(content),
          'afterJsonEncoded': jsonEncode(fixed),
        });
    // #endregion

    return jsonDecode(fixed) as Map<String, dynamic>;
  }

  /// Optimized JSON escape sequence fixer using batched regex replacements
  ///
  /// NOTE: We deliberately do NOT treat `\b`, `\f`, `\r`, `\t` as pre-existing
  /// valid JSON escapes here, even though they technically are in the JSON
  /// spec. This function only runs as a fallback when the model's response
  /// failed to parse as JSON in the first place, which means the model wrote
  /// raw, unescaped backslashes throughout (e.g. for LaTeX like `\frac`,
  /// `\boxed`, `\right`, `\tan`, `\theta`). If we "protect" `\b`/`\f`/`\r`/`\t`
  /// as already-valid escapes, we end up decoding `\f` in `\frac` as an actual
  /// form-feed control character, silently eating the `f` and corrupting the
  /// LaTeX (observed as `\frac` rendering as `<FF>rac`). `\n` is the one
  /// exception: this app's prompt relies on the model emitting real `\n` for
  /// line breaks between steps, and that usage is unambiguous in practice, so
  /// it stays protected.
  static String _fixJsonEscapeSequences(String json) {
    const placeholderStart = '\x00PE\x00';
    const placeholderEnd = '\x00PE_END\x00';
    
    final validEscapes = ['\\\\', '\\"', '\\/', '\\n'];
    
    var result = json;
    
    for (final escape in validEscapes) {
      final placeholder = '$placeholderStart${escape.hashCode}$placeholderEnd';
      result = result.replaceAll(escape, placeholder);
    }
    
    result = result.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) => '\x00PE_UNICODE${match.group(1)!}\x00PE_END',
    );
    
    result = result.replaceAll('\\', '\\\\');
    
    for (final escape in validEscapes) {
      final placeholder = '$placeholderStart${escape.hashCode}$placeholderEnd';
      result = result.replaceAll(placeholder, escape);
    }
    
    result = result.replaceAllMapped(
      RegExp(r'\x00PE_UNICODE([0-9a-fA-F]{4})\x00PE_END'),
      (match) => '\\u${match.group(1)}',
    );
    
    return result;
  }

  /// Image compression worker for background isolate
  /// Uses a separate isolate with its own event loop to handle async image ops
  static Future<Uint8List> _compressImageWorker(Uint8List imageBytes) async {
    const targetSize = 200 * 1024; // 200KB
    
    if (imageBytes.length <= targetSize) {
      return imageBytes;
    }

    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final scale = (targetSize / imageBytes.length).clamp(0.3, 0.9);
    final newWidth = (image.width * scale).round();
    final newHeight = (image.height * scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble());
    
    canvas.drawImageRect(image, srcRect, dstRect, ui.Paint());
    
    final picture = recorder.endRecording();
    final resizedImage = await picture.toImage(newWidth, newHeight);
    
    final byteData = await resizedImage.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    resizedImage.dispose();
    
    return byteData!.buffer.asUint8List();
  }
}
