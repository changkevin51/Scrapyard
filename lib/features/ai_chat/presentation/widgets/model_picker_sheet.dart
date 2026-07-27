import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../domain/models/gemini_model.dart';
import '../providers/chat_providers.dart';

Future<void> showModelPickerSheet(BuildContext context) {
  return showScrapSheet(
    context: context,
    backgroundColor: ScrapTheme.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ScrapTheme.borderRadiusDefault),
      ),
    ),
    builder: (_) => const ModelPickerSheet(),
  );
}

class ModelPickerSheet extends ConsumerWidget {
  const ModelPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(chatModelProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ScrapTheme.kraft,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const ScrapStampLabel(text: '⟨ Models ⟩'),
          const SizedBox(height: 8),
          Text(
            'AI Model',
            style: ScrapTextStyles.heading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Used for chat and as the preferred Smelt model.',
            style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
          ),
          const SizedBox(height: 20),
          ...GeminiChatModel.all.map((m) {
            final sel = m.id == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ScrapPressable(
                scale: 0.98,
                onTap: () {
                  ScrapFeedback.tap();
                  ref.read(chatModelProvider.notifier).setModel(m.id);
                  Navigator.pop(context);
                },
                child: AnimatedContainer(
                  duration: ScrapMotion.fast,
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: sel ? ScrapTheme.accentSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? ScrapTheme.accent : ScrapTheme.dividers,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: ScrapTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? ScrapTheme.accent
                              : ScrapTheme.primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.blurb,
                        style: ScrapTextStyles.caption.copyWith(
                          color: ScrapTheme.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
