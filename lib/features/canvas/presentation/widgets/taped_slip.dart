import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../../../ai_engine/presentation/widgets/latex_markdown_view.dart';
import '../providers/canvas_providers.dart';

/// Kraft slip taped beside a problem — persisted Smelt result on the page.
class TapedSlipOverlay extends ConsumerWidget {
  final CanvasTextItem item;

  const TapedSlipOverlay({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = item.tapedSteps?.trim();
    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          ref.read(canvasTextNodesProvider.notifier).upsert(
                item.copyWith(position: item.position + d.delta),
              );
        },
        child: Transform.rotate(
          angle: -1.2 * math.pi / 180,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  decoration: BoxDecoration(
                    color: ScrapTheme.cardSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: ScrapTheme.kraft.withValues(alpha: 0.85),
                    ),
                    boxShadow: ScrapTheme.deskShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '⟨ taped ⟩',
                        style: ScrapTextStyles.stamp.copyWith(
                          fontSize: 9,
                          color: ScrapTheme.mutedText,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (item.text.trim().isNotEmpty)
                        LatexMarkdownView(
                          text: item.text,
                          compact: true,
                          baseStyle: ScrapTextStyles.body.copyWith(
                            fontSize: 16,
                            color: ScrapTheme.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (steps != null && steps.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        LatexMarkdownView(
                          text: steps,
                          compact: true,
                          baseStyle: ScrapTextStyles.body.copyWith(
                            fontSize: 13,
                            color: ScrapTheme.bodyText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: -7,
                  left: 22,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Container(
                      width: 52,
                      height: 14,
                      decoration: BoxDecoration(
                        color: ScrapTheme.tape.withValues(alpha: 0.92),
                        border: Border.all(
                          color: ScrapTheme.kraft.withValues(alpha: 0.6),
                          width: 0.6,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => ref
                        .read(canvasTextNodesProvider.notifier)
                        .deleteIds([item.id]),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: ScrapTheme.mutedText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
