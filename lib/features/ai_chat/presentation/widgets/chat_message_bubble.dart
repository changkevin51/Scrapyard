import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../ai_engine/presentation/widgets/latex_markdown_view.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/gemini_model.dart';
import 'chat_suggestion_chips.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isStreaming;
  final String? streamingOverride;
  final ValueChanged<String>? onSuggestionTap;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.streamingOverride,
    this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final content = streamingOverride ?? message.content;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? ScrapTheme.accentSurface
                    : ScrapTheme.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isUser
                      ? ScrapTheme.accent.withValues(alpha: 0.25)
                      : ScrapTheme.dividers,
                ),
                boxShadow: isUser ? null : ScrapTheme.subtleShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUser)
                    SelectableText(
                      content,
                      style: ScrapTextStyles.body.copyWith(
                        fontSize: 14,
                        color: ScrapTheme.primaryText,
                      ),
                    )
                  else if (message.isError)
                    Text(
                      content,
                      style: ScrapTextStyles.body.copyWith(
                        fontSize: 13,
                        color: Colors.redAccent,
                      ),
                    )
                  else
                    LatexMarkdownView(
                      text: content + (isStreaming ? ' ▌' : ''),
                      baseStyle: ScrapTextStyles.body.copyWith(
                        fontSize: 13,
                        height: 1.5,
                        color: ScrapTheme.bodyText,
                      ),
                    ),
                  if (!isUser && !isStreaming && !message.isError) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.modelUsed != null)
                          Text(
                            'Powered by ${GeminiChatModel.displayLabel(message.modelUsed!)}',
                            style: ScrapTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: ScrapTheme.mutedText,
                            ),
                          ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Copied',
                                  style: ScrapTextStyles.caption
                                      .copyWith(color: Colors.white),
                                ),
                                backgroundColor: ScrapTheme.accent,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(
                            Icons.copy_outlined,
                            size: 14,
                            color: ScrapTheme.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!isUser &&
              !isStreaming &&
              message.suggestions.isNotEmpty &&
              onSuggestionTap != null) ...[
            const SizedBox(height: 8),
            ChatSuggestionChips(
              suggestions: message.suggestions,
              onSelected: onSuggestionTap!,
            ),
          ],
        ],
      ),
    );
  }
}
