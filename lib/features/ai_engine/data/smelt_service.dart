import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models/smelt_response.dart';

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
  /// If imageBytes is null, sends a text-only request
  Future<SmeltResponse> analyzeSelection(Uint8List? imageBytes) async {
    // final apiKey = await _storage.read(key: _apiKeyKey);
    final apiKey = '[GEMINI KEY HERE]';
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API key not configured');
    }

    String? base64Image;
    if (imageBytes != null) {
      // Compress image if needed (target ~500KB to save tokens)
      final compressedImage = await _compressImageIfNeeded(imageBytes);
      base64Image = base64Encode(compressedImage);
    }

    // Try each model in order until one succeeds
    for (final model in _models) {
      try {
        final response = await _callGemini(apiKey, model, base64Image);
        return response;
      } catch (e) {
        // If rate limited or unavailable, try next model
        if (e.toString().contains('429') || 
            e.toString().contains('RESOURCE_EXHAUSTED') ||
            e.toString().contains('rate') ||
            e.toString().contains('quota')) {
          continue;
        }
        // For other errors, also try next model
        if (model == _models.last) {
          throw Exception('All Gemini models failed: $e');
        }
      }
    }

    throw Exception('All Gemini models are unavailable');
  }

  Future<SmeltResponse> _callGemini(String apiKey, String model, String? base64Image) async {
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

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('No response from Gemini');
      }
      
      final content = candidates[0]['content']['parts'][0]['text'] as String;
      
      try {
        final jsonResponse = jsonDecode(content);
        return SmeltResponse.fromJson(jsonResponse, model);
      } on FormatException catch (e) {
        // Log the full response for debugging
        print('=== GEMINI JSON PARSE ERROR ===');
        print('Error: $e');
        print('Raw content from Gemini:');
        print(content);
        print('=== END GEMINI RESPONSE ===');
        
        // Try to fix common escape sequence issues
        final fixedContent = _fixJsonEscapeSequences(content);
        print('=== FIXED CONTENT ===');
        print(fixedContent);
        print('=== END FIXED CONTENT ===');
        try {
          final jsonResponse = jsonDecode(fixedContent);
          return SmeltResponse.fromJson(jsonResponse, model);
        } catch (e2) {
          print('=== SECOND PARSE ERROR ===');
          print('Error: $e2');
          print('=== END SECOND PARSE ERROR ===');
          throw Exception('Failed to parse Gemini response (even after fixing escapes): $e2\nRaw response: $content');
        }
      }
    } else if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded (429)');
    } else {
      throw Exception('Gemini API error: ${response.statusCode} - ${response.body}');
    }
  }

  /// Fix common JSON escape sequence issues in Gemini responses
  /// Gemini sometimes returns raw backslashes like `\(` which are invalid in JSON
  String _fixJsonEscapeSequences(String json) {
    // Process character by character to handle escape sequences properly
    final buffer = StringBuffer();
    var i = 0;
    
    while (i < json.length) {
      if (json[i] == '\\' && i + 1 < json.length) {
        final nextChar = json[i + 1];
        
        // Check if this is a valid JSON escape sequence
        final isValidEscape = nextChar == '\\' || 
                              nextChar == '"' || 
                              nextChar == '/' ||
                              nextChar == 'b' ||
                              nextChar == 'f' ||
                              nextChar == 'n' ||
                              nextChar == 'r' ||
                              nextChar == 't' ||
                              nextChar == 'u';
        
        if (isValidEscape) {
          // Keep valid escape sequences as-is
          buffer.write('\\');
          buffer.write(nextChar);
          i += 2;
          
          // Handle \uXXXX sequences
          if (nextChar == 'u' && i + 4 <= json.length) {
            buffer.write(json.substring(i, i + 4));
            i += 4;
          }
        } else {
          // Invalid escape - double the backslash
          buffer.write('\\\\');
          buffer.write(nextChar);
          i += 2;
        }
      } else {
        buffer.write(json[i]);
        i++;
      }
    }
    
    return buffer.toString();
  }

  /// Compress image if it's too large (target ~500KB)
  Future<Uint8List> _compressImageIfNeeded(Uint8List imageBytes) async {
    const targetSize = 500 * 1024; // 500KB
    
    if (imageBytes.length <= targetSize) {
      return imageBytes;
    }

    // Decode the image
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Calculate new dimensions to reduce size
    final scale = (targetSize / imageBytes.length).clamp(0.3, 0.9);
    final newWidth = (image.width * scale).round();
    final newHeight = (image.height * scale).round();

    // Create a recorder to resize
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble());
    
    canvas.drawImageRect(image, srcRect, dstRect, ui.Paint());
    
    final picture = recorder.endRecording();
    final resizedImage = await picture.toImage(newWidth, newHeight);
    
    // Convert back to bytes
    final byteData = await resizedImage.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    resizedImage.dispose();
    
    return byteData!.buffer.asUint8List();
  }
}