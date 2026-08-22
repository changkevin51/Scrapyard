import 'package:flutter/material.dart';

import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_tilt.dart';
import '../../domain/guide_content.dart';
import 'guide_mark.dart';

class GuideSectionCard extends StatelessWidget {
  final GuideSection section;
  final int seed;
  final VoidCallback onTap;

  const GuideSectionCard({
    super.key,
    required this.section,
    required this.seed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScrapTilt(
      seed: seed,
      maxDegrees: 0.9,
      child: ScrapPressable(
        scale: 0.98,
        onTap: () {
          ScrapFeedback.tap();
          onTap();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
          decoration: BoxDecoration(
            color: ScrapTheme.cardSurface,
            borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            border: Border.all(color: ScrapTheme.dividers),
            boxShadow: ScrapTheme.deskShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ScrapTheme.accentSurface,
                  borderRadius: BorderRadius.circular(
                    ScrapTheme.borderRadiusSmall,
                  ),
                  border: Border.all(
                    color: ScrapTheme.kraft.withValues(alpha: 0.85),
                    width: 0.75,
                  ),
                ),
                child: Center(
                  child: GuideMark(
                    icon: section.icon,
                    glyph: section.glyph,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: ScrapTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ScrapTheme.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.subtitle,
                      style: ScrapTextStyles.caption.copyWith(
                        color: ScrapTheme.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: ScrapTheme.mutedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
