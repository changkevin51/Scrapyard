import 'package:flutter/material.dart';

import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_tilt.dart';

class GuideLogoLockup extends StatelessWidget {
  final double width;

  const GuideLogoLockup({super.key, this.width = 108});

  @override
  Widget build(BuildContext context) {
    return ScrapTilt(
      seed: 23,
      maxDegrees: 2.4,
      child: Image.asset(
        'assets/images/HomeLogo.png',
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

/// Tiny splash face. Tap it.
class GuideLooseScrapEgg extends StatelessWidget {
  const GuideLooseScrapEgg({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ScrapPressable(
        scale: 0.94,
        onTap: () {
          ScrapFeedback.tap();
          showPaperToast(context, '⟨ loose scrap ⟩');
        },
        child: ScrapTilt(
          seed: 9,
          maxDegrees: 12,
          child: Opacity(
            opacity: 0.55,
            child: Image.asset(
              'assets/images/SplashLogo.png',
              width: 44,
              height: 44,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

class GuideTopicFooter extends StatelessWidget {
  const GuideTopicFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        children: [
          Opacity(
            opacity: 0.45,
            child: Image.asset(
              'assets/images/HomeLogo.png',
              width: 92,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const Spacer(),
          const ScrapStampLabel(text: '⟨ filed ⟩', tiltDegrees: 2),
        ],
      ),
    );
  }
}
