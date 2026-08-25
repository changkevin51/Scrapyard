import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Gemini REST helpers. The API key is sent as a header, never in the URL.
class GeminiApi {
  GeminiApi._();

  static const _origin = 'https://generativelanguage.googleapis.com/v1beta/models';

  static const geminiTermsUrl = 'https://ai.google.dev/gemini-api/terms';
  static const aiStudioKeyUrl = 'https://aistudio.google.com/app/apikey';
  static const privacyPolicyUrl =
      'https://github.com/changkevin51/Scrapyard/blob/main/PRIVACY.md';

  static Uri generateContent(String model) =>
      Uri.parse('$_origin/$model:generateContent');

  static Uri streamGenerateContent(String model) =>
      Uri.parse('$_origin/$model:streamGenerateContent?alt=sse');

  static Map<String, String> headers(String apiKey) => {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };

  /// Block medium-and-above harm on the four standard Gemini categories.
  static const List<Map<String, String>> safetySettings = [
    {
      'category': 'HARM_CATEGORY_HARASSMENT',
      'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
    },
    {
      'category': 'HARM_CATEGORY_HATE_SPEECH',
      'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
    },
    {
      'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
      'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
    },
    {
      'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
      'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
    },
  ];

  static const safetyBlockedMessage =
      'Gemini blocked this reply for safety. Try a different selection, or report it if you think that was a mistake.';

  /// Throws when Gemini refused the prompt or finished for a safety reason.
  static void throwIfSafetyBlocked(Map<String, dynamic> data) {
    final prompt = data['promptFeedback'];
    if (prompt is Map) {
      final reason = prompt['blockReason']?.toString();
      if (reason != null &&
          reason.isNotEmpty &&
          reason != 'BLOCK_REASON_UNSPECIFIED') {
        throw Exception('Gemini safety block: $reason');
      }
    }
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final candidate = candidates.first;
      if (candidate is Map) {
        final finish = candidate['finishReason']?.toString();
        if (finish == 'SAFETY' ||
            finish == 'PROHIBITED_CONTENT' ||
            finish == 'BLOCKLIST' ||
            finish == 'SPII') {
          throw Exception('Gemini safety block: $finish');
        }
      }
    }
  }

  static FlutterSecureStorage secureStorage() => const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );

  /// Short error for UI and chat history — never include HTTP bodies or keys.
  static String userFacingError(Object error) {
    final lower = error.toString().toLowerCase();
    if (lower.contains('no gemini api key')) {
      return 'No Gemini API key set. Open Settings to add your free key.';
    }
    if (lower.contains('api_key_invalid') ||
        lower.contains('api key not valid') ||
        lower.contains('invalid api key') ||
        lower.contains('key was rejected')) {
      return 'That API key was rejected. Check it in Settings.';
    }
    if (lower.contains('429') ||
        lower.contains('resource_exhausted') ||
        lower.contains('rate limit')) {
      return 'Gemini is rate-limited right now. Try again in a moment.';
    }
    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return "Couldn't reach Gemini. Check your connection.";
    }
    if (lower.contains('safety block')) {
      return safetyBlockedMessage;
    }
    if (lower.contains('parse')) {
      return "Couldn't read Gemini's reply. Try Smelt again.";
    }
    return 'Something went wrong. Try again.';
  }
}

void debugOnlyPrint(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
