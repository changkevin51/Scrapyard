import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_overlays.dart';
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
                  if (isUser && message.image != null) ...[
                    _MessageImageThumbnail(bytes: message.image!),
                    if (content.isNotEmpty) const SizedBox(height: 8),
                  ],
                  if (isUser)
                    if (content.isNotEmpty)
                      SelectableText(
                        content,
                        style: ScrapTextStyles.body.copyWith(
                          fontSize: 14,
                          color: ScrapTheme.primaryText,
                        ),
                      )
                    else
                      const SizedBox.shrink()
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
                    if (message.modelFallbackNote != null) ...[
                      Text(
                        message.modelFallbackNote!,
                        style: ScrapTextStyles.caption.copyWith(
                          fontSize: 10,
                          color: ScrapTheme.secondaryText,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
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
                            showPaperToast(context, 'Copied');
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

class _MessageImageThumbnail extends StatelessWidget {
  final Uint8List bytes;

  const _MessageImageThumbnail({required this.bytes});

  void _openFull(BuildContext context) {
    showScrapDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFull(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180, maxWidth: 240),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
