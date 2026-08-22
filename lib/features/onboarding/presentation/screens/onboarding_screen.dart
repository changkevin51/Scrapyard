import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../providers/smelt_guide_provider.dart';

const onboardingCompletedPrefsKey = 'onboarding_completed';

/// Single kraft sheet — the paper teaches the desk. Not a multi-page wizard.
class OnboardingScreen extends ConsumerWidget {
  final bool replayGuide;

  const OnboardingScreen({super.key, this.replayGuide = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ScrapTheme.background,
      body: Stack(
        children: [
          const Positioned.fill(child: PaperGrain(opacity: 0.04)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: SingleChildScrollView(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ScrapStampLabel(text: '⟨ scrapyard ⟩'),
                      const SizedBox(height: 20),
                      Text(
                        'Scrap in, solutions out.',
                        style: ScrapTextStyles.heading.copyWith(fontSize: 28),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Scribble out a problem, select it, and the app works through it with you step by step.',
                        style: ScrapTextStyles.body.copyWith(
                          color: ScrapTheme.secondaryText,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Use Ask (bottom-right) to clarify or ask follow-up questions.',
                        style: ScrapTextStyles.body.copyWith(
                          color: ScrapTheme.secondaryText,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Smelt send the scraps you select to Google Gemini, using your own API key. You may learn more about this app in the guide.',
                        style: ScrapTextStyles.body.copyWith(
                          color: ScrapTheme.secondaryText,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 36),
                      PaperButton(
                        label: 'Get to the desk',
                        variant: PaperButtonVariant.primary,
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool(
                            onboardingCompletedPrefsKey,
                            true,
                          );
                          if (context.mounted) context.go('/');
                          if (replayGuide) {
                            await ref
                                .read(smeltGuideProvider.notifier)
                                .startFromHome(force: true);
                          }
                        },
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
