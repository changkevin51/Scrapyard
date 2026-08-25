import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Public Vercel function URL. Not a secret — the Resend key stays on the
/// server (Vercel env `RESEND_API_KEY`, or `feedback-api/.env.local` for
/// `vercel dev`). Replace this after deploying `feedback-api`.
const kFeedbackEndpoint =
    'https://scrapyard-inky-eight.vercel.app/api/feedback';

const kFeedbackAppVersion = '1.0.0';
const kFeedbackMinMessageLength = 8;
const kFeedbackMaxMessageLength = 4000;

enum FeedbackKind { bug, idea, other, report }

extension FeedbackKindLabel on FeedbackKind {
  String get id => name;

  String get label => switch (this) {
        FeedbackKind.bug => 'Bug',
        FeedbackKind.idea => 'Idea',
        FeedbackKind.other => 'Other',
        FeedbackKind.report => 'Report',
      };
}

class FeedbackResult {
  final bool success;
  final String message;

  const FeedbackResult({required this.success, required this.message});
}

String feedbackPlatformLabel() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform.name;
}

class FeedbackService {
  Future<FeedbackResult> send({
    required FeedbackKind kind,
    required String message,
    String? email,
    String? reportedContent,
  }) async {
    final trimmed = message.trim();
    if (trimmed.length < kFeedbackMinMessageLength) {
      return const FeedbackResult(
        success: false,
        message: 'A little more detail helps — eight characters at least.',
      );
    }
    if (trimmed.length > kFeedbackMaxMessageLength) {
      return const FeedbackResult(
        success: false,
        message: 'That scrap is a bit long. Trim it and try again.',
      );
    }

    final reply = email?.trim() ?? '';
    if (reply.isNotEmpty && !_looksLikeEmail(reply)) {
      return const FeedbackResult(
        success: false,
        message: 'That email does not look right.',
      );
    }

    final payload = <String, dynamic>{
      'kind': kind.id,
      'message': trimmed,
      'version': kFeedbackAppVersion,
      'platform': feedbackPlatformLabel(),
      'website': '',
      if (reply.isNotEmpty) 'email': reply,
      if (reportedContent != null && reportedContent.trim().isNotEmpty)
        'reportedContent': reportedContent.trim(),
    };

    try {
      final response = await http
          .post(
            Uri.parse(kFeedbackEndpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const FeedbackResult(
          success: true,
          message: "Thanks — we'll read this scrap.",
        );
      }

      return FeedbackResult(
        success: false,
        message: _friendlyError(response.statusCode, response.body),
      );
    } on TimeoutException {
      return const FeedbackResult(
        success: false,
        message: "Couldn't send just now. Check your connection.",
      );
    } catch (_) {
      return const FeedbackResult(
        success: false,
        message: "Couldn't send just now. Check your connection.",
      );
    }
  }

  static bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 0 || at == value.length - 1) return false;
    final dot = value.indexOf('.', at + 1);
    return dot > at + 1 && dot < value.length - 1 && !value.contains(' ');
  }

  static String _friendlyError(int statusCode, String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data['error'] is String) {
        final error = (data['error'] as String).toLowerCase();
        if (error.contains('not configured')) {
          return 'Feedback is not set up on this build yet.';
        }
        if (error.contains('email')) {
          return 'That email does not look right.';
        }
        if (error.contains('too short')) {
          return 'A little more detail helps — eight characters at least.';
        }
        if (error.contains('too long')) {
          return 'That scrap is a bit long. Trim it and try again.';
        }
      }
    } catch (_) {}

    if (statusCode == 429) {
      return 'A few scraps just landed. Try again in a moment.';
    }
    return "Couldn't send just now. Try again.";
  }
}
