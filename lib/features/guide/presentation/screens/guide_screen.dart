import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_grain.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../onboarding/presentation/providers/smelt_guide_provider.dart';
import '../../domain/guide_content.dart';
import '../widgets/guide_section_card.dart';
import '../widgets/guide_stickers.dart';

class GuideScreen extends ConsumerWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        shape: const Border(
          bottom: BorderSide(color: ScrapTheme.dividers, width: 1),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: PaperGrain(opacity: 0.03)),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 640;
              const gap = 14.0;
              final cardWidth = twoCol
                  ? (constraints.maxWidth - 48 - gap) / 2
                  : constraints.maxWidth - 48;

              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScrapStampLabel(text: '⟨ how to ⟩'),
                            SizedBox(height: 16),
                          ],
                        ),
                      ),
                      GuideLogoLockup(width: twoCol ? 128 : 96),
                    ],
                  ),
                  Text(
                    'How to use Scrapyard.',
                    style: ScrapTextStyles.heading.copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tools, Smelt, Ask, files, and a few gestures worth knowing.',
                    style: ScrapTextStyles.body.copyWith(
                      color: ScrapTheme.secondaryText,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PaperButton(
                      label: 'Replay the tour',
                      variant: PaperButtonVariant.primary,
                      icon: Icons.replay,
                      onPressed: () async {
                        final guide = ref.read(smeltGuideProvider.notifier);
                        if (!context.mounted) return;
                        context.go('/');
                        await guide.startFromHome(force: true);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TapeStrip(
                      label: '⟨ filed ⟩',
                      tiltDegrees: -2.5,
                      margin: EdgeInsets.only(left: 4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: ScrapTheme.dividers),
                  const SizedBox(height: 20),
                  Text(
                    'SECTIONS',
                    style: ScrapTextStyles.stamp.copyWith(
                      fontSize: 10,
                      color: ScrapTheme.mutedText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < GuideSection.all.length; i++)
                        SizedBox(
                          width: cardWidth,
                          child: GuideSectionCard(
                            section: GuideSection.all[i],
                            seed: 11 + i * 17,
                            onTap: () => context.push(
                              '/guide/${GuideSection.all[i].id}',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: PaperChit(
                      seed: 12,
                      tiltDegrees: 3.5,
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        "⟨ don't smelt lunch ⟩",
                        style: TextStyle(
                          fontFamily: 'Courier Prime',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: ScrapTheme.accent,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const GuideLooseScrapEgg(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
