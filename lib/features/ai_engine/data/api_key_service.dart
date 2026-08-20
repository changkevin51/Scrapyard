import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'smelt_service.dart';
import 'gemini_api.dart';

/// Result of testing a Gemini API key against the cheapest model.
class ApiKeyTestResult {
  final bool success;
  final String message;
  final String? modelReply;

  const ApiKeyTestResult({
    required this.success,
    required this.message,
    this.modelReply,
  });
}

/// Persists and validates the user's Gemini API key.
class ApiKeyService {
  final FlutterSecureStorage _storage;

  ApiKeyService(this._storage);

  Future<String?> read() async {
    final value = await _storage.read(key: SmeltService.apiKeyStorageKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: SmeltService.apiKeyStorageKey, value: trimmed);
  }

  Future<void> clear() async {
    await _storage.delete(key: SmeltService.apiKeyStorageKey);
  }

  /// Masks a key for display, e.g. `AIza••••••3f9c`.
  static String mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length <= 4) return '••••••••';
    final suffix = trimmed.substring(trimmed.length - 4);
    return '••••••••$suffix';
  }

  /// Sends a tiny prompt to the cheapest Gemini model to verify the key.
  Future<ApiKeyTestResult> test(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return const ApiKeyTestResult(
        success: false,
        message: 'Paste your API key first.',
      );
    }

    final model = SmeltService.cheapestModel;
    final url = GeminiApi.generateContent(model);

    final body = {
      'contents': [
        {
          'parts': [
            {'text': 'Reply with the single word: ok'},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 8,
      },
    };

    try {
      final response = await http
          .post(
            url,
            headers: GeminiApi.headers(trimmed),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        String? reply;
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              reply = (parts[0]['text'] as String?)?.trim();
            }
          }
        } catch (_) {
          // Ignore parse issues — a 200 still means the key works.
        }

        return ApiKeyTestResult(
          success: true,
          message: 'Connected successfully.',
          modelReply: reply,
        );
      }

      return ApiKeyTestResult(
        success: false,
        message: _friendlyError(response.statusCode, response.body),
      );
    } on TimeoutException {
      return const ApiKeyTestResult(
        success: false,
        message: "Couldn't reach Google. Check your connection.",
      );
    } catch (_) {
      return const ApiKeyTestResult(
        success: false,
        message: "Couldn't reach Google. Check your connection.",
      );
    }
  }

  static String _friendlyError(int statusCode, String body) {
    final lower = body.toLowerCase();

    if (lower.contains('api_key_invalid') ||
        lower.contains('api key not valid') ||
        lower.contains('invalid api key')) {
      return 'That key was rejected. Check you copied the whole key.';
    }
    if (statusCode == 400) {
      return "Couldn't verify the key with Gemini. Try again, or check the default model is available on this key.";
    }
    if (statusCode == 403) {
      return "Key valid but the Generative Language API isn't enabled for this project.";
    }
    if (statusCode == 429) {
      return "Key works, but you're rate limited right now.";
    }
    if (statusCode == 404) {
      return 'Model unavailable. Try again in a moment.';
    }
    return 'Something went wrong ($statusCode). Try again.';
  }
}
