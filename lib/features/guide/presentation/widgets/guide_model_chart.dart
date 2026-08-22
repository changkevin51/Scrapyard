import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../ai_chat/domain/models/gemini_model.dart';
import '../../domain/guide_content.dart';

/// Paper comparison of models: speed ticks and relative quota tightness.
class GuideModelChart extends StatelessWidget {
  const GuideModelChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        border: Border.all(color: ScrapTheme.dividers),
        boxShadow: ScrapTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ScrapStampLabel(text: '⟨ comparison ⟩', tiltDegrees: -1),
                const SizedBox(height: 10),
                Text(
                  'Speed and limits',
                  style: ScrapTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ScrapTheme.primaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Free-tier limits on a typical AI Studio key. RPM is requests per minute. RPD is requests per day.',
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.secondaryText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: ScrapTheme.dividers),
          for (var i = 0; i < GeminiChatModel.all.length; i++) ...[
            if (i > 0) Container(height: 1, color: ScrapTheme.dividers),
            _ModelRow(model: GeminiChatModel.all[i]),
          ],
          Container(height: 1, color: ScrapTheme.dividers),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If Gemini returns a rate limit, Scrapyard tries the next model in the same family, then a lighter one. Paid projects can have higher caps and speed. Check yours at ${GuideModelInfo.studioRateLimitsUrl}',
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.mutedText,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Speed and availability can vary with time of day and traffic.',
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.mutedText,
                    height: 1.45,
                    fontSize: 13,
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

class _ModelRow extends StatelessWidget {
  final GeminiChatModel model;

  const _ModelRow({required this.model});

  @override
  Widget build(BuildContext context) {
    final ticks = GuideModelInfo.speedTicks(model);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.label,
            style: ScrapTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: ScrapTheme.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _SpeedTicks(filled: ticks),
              const SizedBox(width: 8),
              Text(
                model.mayTakeLonger ? 'Slower' : 'Fast',
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.mutedText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LimitChip(
                label: 'RPM',
                value: GuideModelInfo.rpm(model),
              ),
              const SizedBox(width: 16),
              _LimitChip(
                label: 'RPD',
                value: GuideModelInfo.rpd(model),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitChip extends StatelessWidget {
  final String label;
  final String value;

  const _LimitChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: ScrapTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: ScrapTheme.accent,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: ScrapTextStyles.stamp.copyWith(
            fontSize: 10,
            color: ScrapTheme.mutedText,
          ),
        ),
      ],
    );
  }
}

class _SpeedTicks extends StatelessWidget {
  final int filled;

  const _SpeedTicks({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < GuideModelInfo.maxSpeedTicks; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled
                  ? ScrapTheme.accent
                  : ScrapTheme.dividers,
            ),
          ),
      ],
    );
  }
}
