import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../ai_chat/domain/models/gemini_model.dart';
import '../domain/models/smelt_response.dart';
import '../_debug_log_helper.dart';

/// Callback for streaming progress updates
typedef SmeltProgressCallback = void Function({
  String? partialAnswer,
  String? partialSteps,
  List<String>? partialSuggestions,
  bool isComplete,
  String? error,
});

/// Result from a streaming smelt operation
class SmeltStreamResult {
  final SmeltResponse response;
  final String modelUsed;
  final String? requestedModel;
  final String? fallbackReason;

  const SmeltStreamResult({
    required this.response,
    required this.modelUsed,
    this.requestedModel,
    this.fallbackReason,
  });

  bool get didFallback =>
      requestedModel != null &&
      fallbackReason != null &&
      requestedModel != modelUsed;
}

/// Service for the Smelt AI feature using Gemini API with fallback chain
class SmeltService {
  final FlutterSecureStorage _storage;

  /// Shared storage key used by [ApiKeyService] and Smelt.
  static const String apiKeyStorageKey = 'gemini_api_key';

  /// User-facing message when no API key is configured.
  static const String missingApiKeyMessage =
      'No Gemini API key set. Open Settings > Gemini API Key to add your free key.';

  /// Cheapest / default model — used for API key testing.
  static String get cheapestModel => GeminiChatModel.defaultModel.id;

  SmeltService(this._storage);

  /// Analyze the selected region image and return AI response
  Future<SmeltResponse> analyzeSelection(Uint8List? imageBytes) async {
    final result = await analyzeSelectionStream(imageBytes);
    return result.response;
  }

  /// Analyze with streaming support for faster perceived response time.
  ///
  /// Code execution is available on the Gemini request; the model chooses
  /// whether to use it. When [forceCodeExecution] is true, the prompt
  /// requires the model to verify its answer by running code.
  Future<SmeltStreamResult> analyzeSelectionStream(
    Uint8List? imageBytes, {
    String? preferredModel,
    String? selectedText,
    bool singleModel = false,
    bool forceCodeExecution = false,
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

    final requested = preferredModel ?? GeminiChatModel.defaultModel.id;
    final models = singleModel
        ? [requested]
        : GeminiChatModel.fallbackChain(requested);

    Object? lastError;
    String? lastRetryReason;
    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        final response = await _callGemini(
          apiKey,
          model,
          base64Image,
          onProgress,
          forceCodeExecution: forceCodeExecution,
          selectedText: selectedText,
        );
        return SmeltStreamResult(
          response: response.response,
          modelUsed: model,
          requestedModel: i > 0 ? requested : null,
          fallbackReason: i > 0 ? lastRetryReason : null,
        );
      } catch (e) {
        lastError = e;
        if (singleModel || i == models.length - 1) {
          throw Exception('Gemini model failed: $e');
        }
        if (!GeminiChatModel.isRetryableError(e)) {
          rethrow;
        }
        lastRetryReason = GeminiChatModel.describeFallbackReason(e);
      }
    }

    throw Exception('All Gemini models are unavailable: $lastError');
  }

  Future<SmeltStreamResult> _callGemini(
    String apiKey,
    String model,
    String? base64Image,
    SmeltProgressCallback? onProgress, {
    bool forceCodeExecution = false,
    String? selectedText,
  }) async {
    final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

    final forceCodeBlock = forceCodeExecution
        ? '''

6. CODE EXECUTION (REQUIRED):
   - You MUST use the code_execution tool to verify your answer before responding.
   - Write and run Python code that checks or computes the result.
   - Base the final "answer" on the code execution output.
   - Do not skip code execution even if the problem looks simple.
'''
        : '''

6. CODE EXECUTION (OPTIONAL — USE SPARINGLY):
   - You have access to a code_execution tool (Python sandbox). You decide whether to use it.
   - DEFAULT: answer directly WITHOUT code. Do NOT use code for simple arithmetic,
     one-step algebra, definitions, explanations, or anything you can solve confidently by reasoning.
   - USE code ONLY when it clearly helps: multi-step numerical work, large/messy calculations,
     symbolic manipulation you might get wrong by hand, plotting/simulation, or verifying a
     non-trivial result where a mistake is likely.
   - Never run code "just in case" (e.g. 1+1, solve x+2=5, basic derivatives). Prefer no tool call.
''';

    final systemPrompt = '''
You are Scrapyard's AI smelt engine. Analyze the selected canvas content
(handwriting in the image and/or typed text provided below).

IMPORTANT RULES:
1. If this is a MATH question/problem:
   - If there is a clear, concise final result (a number, closed-form expression, short statement):
     Put ONLY that final answer in the "answer" field as LaTeX using \\( ... \\)
     (e.g., "\\(x = 5\\)", "\\(42\\)", "\\(\\frac{\\pi}{2}\\)", "\\(\\frac{x^4}{4} + x^2 + 5x + C\\)")
     Put the step-by-step solution in the "steps" field
   - If there is NO single concise final answer — proofs, "show that…", multi-step
     derivations, constructions, or anything where the work itself is the answer:
     Leave "answer" as an empty string ""
     Put the full solution/proof only in the "steps" field (do NOT duplicate a summary into "answer")
   - Set "isMath" to true

2. If this is NOT a math question:
   - If there is a clear direct answer or short summary, put it in the "answer" field
   - Put any additional details or explanation steps in the "steps" field (can be empty if answer is complete)
   - If the response is inherently a process/series of steps with no punchline answer,
     leave "answer" as "" and put everything in "steps"
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

5. Always include 2–3 short follow-up questions a student would ask next in "suggestions".
   Each question max 6 words. Examples: "Explain in more detail", "Why the chain rule?", "Show another example".
$forceCodeBlock
After any tool use, you MUST respond with ONLY a JSON object in this exact format (no markdown fences):
{
  "answer": "The direct answer here (or empty string \"\" if there is no single concise answer)",
  "steps": "Step-by-step in markdown with LaTeX (or empty string if not needed)",
  "isMath": true or false,
  "suggestions": ["Short question 1", "Short question 2"]
}
''';

    final parts = <Map<String, dynamic>>[
      {'text': systemPrompt},
    ];

    final typed = selectedText?.trim();
    final hasTyped = typed != null && typed.isNotEmpty;

    if (base64Image != null) {
      parts.add({
        'inline_data': {
          'mime_type': 'image/png',
          'data': base64Image,
        },
      });
      final userHint = forceCodeExecution
          ? 'Analyze this selected content. You MUST use code execution to verify the answer, then provide the JSON response.'
          : 'Analyze this selected content and provide the answer. Use code execution only if the problem truly needs it; otherwise answer directly with no tool call.';
      parts.add({'text': userHint});
    }

    if (hasTyped) {
      parts.add({
        'text': 'Typed text from the canvas selection:\n$typed',
      });
    }

    if (base64Image == null && !hasTyped) {
      parts.add({
        'text':
            'No image or typed text available. Please respond that the selection could not be captured.',
      });
    }
    final requestBody = {
      'contents': [
        {
          'parts': parts,
        },
      ],
      // Code execution is available; the model decides whether to call it.
      // JSON mime type is omitted because it is incompatible with tools.
      'tools': [
        {'code_execution': <String, dynamic>{}},
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 2048,
      },
    };

    // Send request and stream the response body chunks
    final request = http.Request('POST', Uri.parse(url))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(requestBody);

    final stream = request.send().timeout(const Duration(seconds: 60));
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

      final content = _extractTextFromCandidate(candidates[0]);
      if (content.isEmpty) {
        throw Exception('No text response from Gemini');
      }
      final codeRuns = _extractCodeRunsFromCandidate(candidates[0]);

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
          partialSuggestions: _parseSuggestions(jsonResponse['suggestions']),
          isComplete: true,
        );

        final responseModel = SmeltResponse.fromJson(
          jsonResponse,
          model,
          codeRuns: codeRuns,
        );
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
            partialSuggestions: _parseSuggestions(jsonResponse['suggestions']),
            isComplete: true,
          );

          final responseModel = SmeltResponse.fromJson(
            jsonResponse,
            model,
            codeRuns: codeRuns,
          );
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

  /// Pull all text parts from a candidate (code-execution responses have
  /// executableCode / codeExecutionResult parts mixed in).
  static String _extractTextFromCandidate(dynamic candidate) {
    if (candidate is! Map) return '';
    final content = candidate['content'];
    if (content is! Map) return '';
    final parts = content['parts'];
    if (parts is! List) return '';

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    return buffer.toString().trim();
  }

  /// Collect executable code + results from a candidate.
  static List<SmeltCodeRun> _extractCodeRunsFromCandidate(dynamic candidate) {
    if (candidate is! Map) return const [];
    final content = candidate['content'];
    if (content is! Map) return const [];
    final parts = content['parts'];
    if (parts is! List) return const [];

    final runs = <SmeltCodeRun>[];
    String? pendingLang;
    String? pendingCode;

    void flush({String output = ''}) {
      final code = pendingCode?.trimRight() ?? '';
      if (code.isEmpty && output.isEmpty) return;
      runs.add(SmeltCodeRun(
        language: pendingLang ?? 'python',
        code: code,
        output: output,
      ));
      pendingLang = null;
      pendingCode = null;
    }

    for (final part in parts) {
      if (part is! Map) continue;

      final exec = part['executableCode'] ?? part['executable_code'];
      if (exec is Map) {
        // Start of a new run — flush any orphaned previous code first.
        if (pendingCode != null) flush();
        pendingLang = (exec['language'] as String? ?? 'PYTHON').toLowerCase();
        pendingCode = exec['code'] as String? ?? '';
      }

      final result =
          part['codeExecutionResult'] ?? part['code_execution_result'];
      if (result is Map) {
        final output = (result['output'] as String? ?? '').trimRight();
        final outcome = result['outcome'] as String?;
        final displayOutput = output.isNotEmpty
            ? output
            : (outcome != null &&
                    outcome.isNotEmpty &&
                    outcome != 'OUTCOME_OK'
                ? 'Outcome: $outcome'
                : '');
        flush(output: displayOutput);
      }
    }

    // Code without a following result part.
    if (pendingCode != null) flush();

    return runs;
  }

  /// Strip optional markdown fences and isolate the outermost JSON object.
  static String _normalizeJsonContent(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      final firstNl = text.indexOf('\n');
      if (firstNl >= 0) text = text.substring(firstNl + 1);
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  /// Worker function for JSON parsing in isolate
  static Map<String, dynamic> _parseJsonWorker(String content) {
    return jsonDecode(_normalizeJsonContent(content)) as Map<String, dynamic>;
  }

  static List<String>? _parseSuggestions(dynamic raw) {
    if (raw is! List) return null;
    final list = raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .take(3)
        .toList();
    return list.isEmpty ? null : list;
  }

  /// Worker function for fixing and parsing JSON in isolate
  static Map<String, dynamic> _fixAndParseJsonWorker(String content) {
    final fixed = _fixJsonEscapeSequences(_normalizeJsonContent(content));

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
