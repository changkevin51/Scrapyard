import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../domain/models/gemini_model.dart';
import '../providers/chat_providers.dart';

/// Result from a one-time model pick (e.g. Smelt "try another model").
class ModelPickerResult {
  final String modelId;
  final bool forceCodeExecution;

  const ModelPickerResult({
    required this.modelId,
    this.forceCodeExecution = false,
  });
}

Future<ModelPickerResult?> showModelPickerSheet(
  BuildContext context, {
  bool oneTime = false,
  String? selectedModelId,
  bool showCodeOption = false,
}) {
  return showScrapSheet<ModelPickerResult?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ScrapTheme.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ScrapTheme.borderRadiusDefault),
      ),
    ),
    builder: (_) => ModelPickerSheet(
      oneTime: oneTime,
      selectedModelId: selectedModelId,
      showCodeOption: showCodeOption,
    ),
  );
}

class ModelPickerSheet extends ConsumerStatefulWidget {
  final bool oneTime;
  final String? selectedModelId;
  final bool showCodeOption;

  const ModelPickerSheet({
    super.key,
    this.oneTime = false,
    this.selectedModelId,
    this.showCodeOption = false,
  });

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  bool _forceCodeExecution = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.oneTime
        ? (widget.selectedModelId ?? ref.watch(chatModelProvider))
        : ref.watch(chatModelProvider);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.top - media.padding.bottom;
    // Leave room for the torn-sheet grabber above this content.
    const grabberAllowance = 32.0;
    final maxHeight = availableHeight * 0.85 - grabberAllowance;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
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
              widget.oneTime
                  ? 'One-time override — your default model stays the same.'
                  : 'Used for chat and as the preferred Smelt model.',
              style:
                  ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
            ),
            if (widget.showCodeOption) ...[
              const SizedBox(height: 16),
              _CodeExecutionToggle(
                value: _forceCodeExecution,
                onChanged: (v) => setState(() => _forceCodeExecution = v),
              ),
            ],
            const SizedBox(height: 20),
            ...GeminiChatModel.all.map((m) {
              final sel = m.id == selected;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ScrapPressable(
                  scale: 0.98,
                  onTap: () {
                    ScrapFeedback.tap();
                    if (widget.oneTime) {
                      Navigator.pop(
                        context,
                        ModelPickerResult(
                          modelId: m.id,
                          forceCodeExecution: _forceCodeExecution,
                        ),
                      );
                    } else {
                      ref.read(chatModelProvider.notifier).setModel(m.id);
                      Navigator.pop(context);
                    }
                  },
                  child: AnimatedContainer(
                    duration: ScrapMotion.fast,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color:
                          sel ? ScrapTheme.accentSurface : Colors.transparent,
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
                        if (m.mayTakeLonger) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 13,
                                color: ScrapTheme.secondaryText.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'May take longer to respond',
                                style: ScrapTextStyles.caption.copyWith(
                                  color: ScrapTheme.secondaryText,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CodeExecutionToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CodeExecutionToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ScrapTheme.codeSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ScrapTheme.dividers),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 18, color: ScrapTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Verify with code',
                      style: ScrapTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: ScrapTheme.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: ScrapTheme.accent.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(
                        'NEW',
                        style: ScrapTextStyles.stamp.copyWith(
                          color: ScrapTheme.accent,
                          fontSize: 8,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Prompt the model to run code to check its answer',
                  style: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.mutedText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PaperSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
