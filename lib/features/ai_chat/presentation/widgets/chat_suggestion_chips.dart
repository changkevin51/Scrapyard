import 'package:flutter/material.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_pressable.dart';

/// Shared chip row for follow-up / starter suggestions.
class ChatSuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final bool wrap;

  const ChatSuggestionChips({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.wrap = true,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final chips = suggestions.map((s) {
      return ScrapPressable(
        scale: 0.95,
        onTap: () {
          ScrapFeedback.tap();
          onSelected(s);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: ScrapTheme.accentSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ScrapTheme.dividers),
          ),
          child: Text(
            s,
            style: ScrapTextStyles.caption.copyWith(
              color: ScrapTheme.accent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }).toList();

    if (wrap) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }
}
