import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../ai_engine/data/gemini_api.dart';

/// In-app privacy policy (same text as repo PRIVACY.md).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ScrapTheme.background,
      appBar: AppBar(
        title: Text(
          'Privacy',
          style: ScrapTextStyles.heading.copyWith(fontSize: 20),
        ),
        backgroundColor: ScrapTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: ScrapTheme.primaryText),
        shape: const Border(
          bottom: BorderSide(color: ScrapTheme.dividers, width: 1),
        ),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('PRIVACY.md'),
        builder: (context, snapshot) {
          final text = snapshot.data ??
              'Scrapyard stores notes on your device. Smelt and study chat '
              'send the content you select, plus your Gemini API key, to Google.\n\n'
              '${GeminiApi.privacyPolicyUrl}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              SelectableText(
                text,
                style: ScrapTextStyles.body.copyWith(
                  color: ScrapTheme.bodyText,
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              SelectableText(
                GeminiApi.privacyPolicyUrl,
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.accent,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
