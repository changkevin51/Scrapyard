import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../domain/guide_content.dart';
import '../widgets/guide_mark.dart';
import '../widgets/guide_model_chart.dart';
import '../widgets/guide_stickers.dart';
import '../widgets/guide_tip_card.dart';

class GuideTopicScreen extends StatelessWidget {
  final String topicId;

  const GuideTopicScreen({super.key, required this.topicId});

  @override
  Widget build(BuildContext context) {
    final section = GuideSection.byId(topicId);
    if (section == null) {
      return Scaffold(
        backgroundColor: ScrapTheme.background,
        appBar: AppBar(
          title: Text(
            'Guide',
            style: ScrapTextStyles.heading.copyWith(fontSize: 20),
          ),
          backgroundColor: ScrapTheme.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: ScrapTheme.primaryText),
        ),
        body: Center(
          child: TextButton(
            onPressed: () => context.go('/guide'),
            child: Text(
              'That page is not in the guide.',
              style: ScrapTextStyles.body.copyWith(color: ScrapTheme.accent),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ScrapTheme.background,
      appBar: AppBar(
        title: Text(
          section.title,
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
      body: Stack(
        children: [
          const Positioned.fill(child: PaperGrain(opacity: 0.03)),
          ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            children: [
              ScrapStampLabel(text: section.stamp),
              const SizedBox(height: 16),
              Text(
                section.title,
                style: ScrapTextStyles.heading.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 8),
              Text(
                section.subtitle,
                style: ScrapTextStyles.body.copyWith(
                  color: ScrapTheme.secondaryText,
                  height: 1.45,
                ),
              ),
              if (section.showToolStrip) ...[
                const SizedBox(height: 24),
                const _ToolStrip(),
              ],
              if (section.showModelChart) ...[
                const SizedBox(height: 24),
                const GuideModelChart(),
              ],
              const SizedBox(height: 24),
              for (var i = 0; i < section.tips.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                GuideTipCard(tip: section.tips[i]),
              ],
              const GuideTopicFooter(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: ScrapTheme.cardSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        border: Border.all(color: ScrapTheme.dividers),
        boxShadow: ScrapTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScrapStampLabel(text: '⟨ toolbar ⟩', tiltDegrees: -1),
          const SizedBox(height: 12),
          Text(
            'Every tool on the bar',
            style: ScrapTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: ScrapTheme.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pen settings (the tune chit) sit after these. Undo and redo are next to them. Two-finger and three-finger taps do the same job.',
            style: ScrapTextStyles.caption.copyWith(
              color: ScrapTheme.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          for (final tool in GuideToolItem.all) _ToolRow(tool: tool),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final GuideToolItem tool;

  const _ToolRow({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: GuideMark(
                icon: tool.icon,
                glyph: tool.glyph,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.label,
                  style: ScrapTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: ScrapTheme.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tool.caption,
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.secondaryText,
                    height: 1.4,
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
