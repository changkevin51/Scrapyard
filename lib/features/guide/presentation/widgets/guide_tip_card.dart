import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../domain/guide_content.dart';
import 'guide_mark.dart';

class GuideTipCard extends StatelessWidget {
  final GuideTip tip;

  const GuideTipCard({super.key, required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        border: Border.all(color: ScrapTheme.dividers),
        boxShadow: ScrapTheme.subtleShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ScrapTheme.accentSurface,
              borderRadius: BorderRadius.circular(
                ScrapTheme.borderRadiusSmall,
              ),
            ),
            child: Center(
              child: GuideMark(
                icon: tip.icon,
                glyph: tip.glyph,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: ScrapTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ScrapTheme.primaryText,
                    height: 1.3,
                  ),
                ),
                if (tip.stamp != null) ...[
                  const SizedBox(height: 8),
                  ScrapStampLabel(text: tip.stamp!, tiltDegrees: -1.2),
                ],
                const SizedBox(height: 8),
                Text(
                  tip.body,
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.bodyText,
                    height: 1.5,
                    fontSize: 14.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
