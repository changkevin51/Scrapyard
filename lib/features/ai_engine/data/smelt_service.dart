import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/smelt_response.dart';

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
  static const String _apiKeyKey = 'gemini_api_key';
  
  // Gemini models in priority order (fallback chain)
  static const List<String> _models = [
    'gemini-3.5-flash',
    'gemini-3-flash-preview',
    'gemini-3.1-flash-lite',
  ];

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
    const apiKey = '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not configured');
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
You are Koto's AI smelt engine. Analyze the handwritten content in the image.

IMPORTANT RULES:
1. If this is a MATH question/problem:
   - Put ONLY the final answer in the "answer" field (e.g., "x = 5", "42", "π/2")
   - Put the step-by-step solution in the "steps" field
   - Set "isMath" to true

2. If this is NOT a math question:
   - Put the main answer/explanation in the "answer" field
   - Put any additional details or explanation steps in the "steps" field (can be empty if answer is complete)
   - Set "isMath" to false

3. For the "steps" field (when needed):
   - Use markdown formatting
   - DO NOT use LaTeX for single letters, variables, numbers, or simple operations in sentences. Write them as plain text inline.
     * Write variables simply as text (e.g., "solve for x", "coefficient of y").
   - For LaTeX math, use these EXACT delimiters:
     * Inline math: \\( ... \\)  (e.g., \\(x^2 + y^2 = r^2\\))
     * Display math: \\[ ... \\]  (e.g., \\[\\int_0^1 x^2 dx = \\frac{1}{3}\\])
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
      // Stream the response body and accumulate chunks
      final accumulated = StringBuffer();
      await for (final chunk in response.stream) {
        accumulated.write(String.fromCharCodes(chunk));
        
        // Try to parse what we have so far for progressive display
        final content = _extractContentFromStreamResponse(accumulated.toString());
        if (content != null && content.isNotEmpty) {
          // Parse JSON progressively
          final parsed = _tryParsePartialJson(content);
          if (parsed != null) {
            onProgress?.call(
              partialAnswer: parsed['answer'] as String?,
              partialSteps: parsed['steps'] as String?,
              isComplete: false,
            );
          }
        }
      }

      final responseBody = accumulated.toString();
      final data = jsonDecode(responseBody);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('No response from Gemini');
      }
      
      final content = candidates[0]['content']['parts'][0]['text'] as String;
      
      try {
        final jsonResponse = await compute(_parseJsonWorker, content);
        // Signal completion with final values
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

  /// Extract content from Gemini response (handles streaming format)
  String? _extractContentFromStreamResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        return candidates[0]['content']['parts'][0]['text'] as String?;
      }
    } catch (_) {
      // Partial JSON may not parse yet
    }
    return null;
  }

  /// Try to parse partial/incomplete JSON for progressive display
  Map<String, dynamic>? _tryParsePartialJson(String content) {
    try {
      // Ensure JSON is complete by adding closing braces if needed
      var normalized = content.trim();
      
      // Count braces to check if complete
      var braceCount = 0;
      var bracketCount = 0;
      var inString = false;
      var escapeNext = false;
      
      for (var i = 0; i < normalized.length; i++) {
        final char = normalized[i];
        
        if (escapeNext) {
          escapeNext = false;
          continue;
        }
        
        if (char == '\\') {
          escapeNext = true;
          continue;
        }
        
        if (char == '"') {
          inString = !inString;
          continue;
        }
        
        if (inString) continue;
        
        if (char == '{') braceCount++;
        if (char == '}') braceCount--;
        if (char == '[') bracketCount++;
        if (char == ']') bracketCount--;
      }
      
      // Add missing closing braces if incomplete
      while (braceCount > 0 || bracketCount > 0) {
        if (braceCount > 0) {
          normalized += '}';
          braceCount--;
        }
        if (bracketCount > 0) {
          normalized += ']';
          bracketCount--;
        }
      }
      
      return jsonDecode(normalized) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Worker function for JSON parsing in isolate
  static Map<String, dynamic> _parseJsonWorker(String content) {
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Worker function for fixing and parsing JSON in isolate
  static Map<String, dynamic> _fixAndParseJsonWorker(String content) {
    final fixed = _fixJsonEscapeSequences(content);
    return jsonDecode(fixed) as Map<String, dynamic>;
  }

  /// Optimized JSON escape sequence fixer using batched regex replacements
  static String _fixJsonEscapeSequences(String json) {
    const placeholderStart = '\x00PE\x00';
    const placeholderEnd = '\x00PE_END\x00';
    
    final validEscapes = ['\\\\', '\\"', '\\/', '\\b', '\\f', '\\n', '\\r', '\\t'];
    
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
