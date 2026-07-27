import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../ai_chat/domain/models/gemini_model.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_chat/presentation/widgets/chat_history_sheet.dart';
import '../../../ai_chat/presentation/widgets/model_picker_sheet.dart';
import '../../../ai_engine/data/api_key_service.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/api_key_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiKeyAsync = ref.watch(apiKeyProvider);
    final key = apiKeyAsync.valueOrNull;
    final hasKey = key != null && key.isNotEmpty;
    final subtitle = hasKey
        ? ApiKeyService.mask(key)
        : 'Not set — tap to add';

    final modelId = ref.watch(chatModelProvider);
    final modelLabel = GeminiChatModel.displayLabel(modelId);
    final conversations = ref.watch(conversationsProvider);
    final chatCount = conversations.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: ScrapTheme.background,
      appBar: AppBar(
        title: Text(
          'Settings',
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
          ListTile(
            title: Text('Gemini API Key', style: ScrapTextStyles.body),
            subtitle: Text(
              subtitle,
              style: ScrapTextStyles.caption.copyWith(
                color: hasKey ? ScrapTheme.secondaryText : ScrapTheme.mutedText,
                fontFamily: hasKey ? 'monospace' : null,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: ScrapTheme.mutedText,
            ),
            onTap: () async {
              ScrapFeedback.tap();
              final saved = await showApiKeyDialog(context, allowSkip: false);
              if (saved == true && context.mounted) {
                final nowHasKey =
                    (ref.read(apiKeyProvider).valueOrNull ?? '').isNotEmpty;
                showPaperToast(
                  context,
                  nowHasKey
                      ? (hasKey ? 'API key updated' : 'API key saved')
                      : 'API key removed',
                );
              }
            },
          ),
          const Divider(color: ScrapTheme.dividers),
          ListTile(
            title: Text('AI Model', style: ScrapTextStyles.body),
            subtitle: Text(
              modelLabel,
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.secondaryText,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: ScrapTheme.mutedText,
            ),
            onTap: () {
              ScrapFeedback.tap();
              showModelPickerSheet(context);
            },
          ),
          const Divider(color: ScrapTheme.dividers),
          ListTile(
            title: Text('Chat History', style: ScrapTextStyles.body),
            subtitle: Text(
              chatCount == 0
                  ? 'No conversations yet'
                  : '$chatCount conversation${chatCount == 1 ? '' : 's'}',
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.mutedText,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: ScrapTheme.mutedText,
            ),
            onTap: () {
              ScrapFeedback.tap();
              showChatHistorySheet(context);
            },
          ),
          const Divider(color: ScrapTheme.dividers),
          ListTile(
            title: Text(
              'Delete all chat history',
              style: ScrapTextStyles.body.copyWith(color: ScrapTheme.inkRed),
            ),
            subtitle: Text(
              'Crush every saved conversation',
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.mutedText,
              ),
            ),
            onTap: chatCount == 0
                ? null
                : () async {
                    ScrapFeedback.warn();
                    final confirmed = await showScrapDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: ScrapTheme.cardSurface,
                        title: Text('Delete all chats?',
                            style: ScrapTextStyles.heading),
                        content: Text(
                          'This will permanently crush all chat history. This cannot be undone.',
                          style: ScrapTextStyles.body,
                        ),
                        actions: [
                          PaperButton(
                            label: 'Cancel',
                            variant: PaperButtonVariant.ghost,
                            compact: true,
                            onPressed: () => Navigator.pop(ctx, false),
                          ),
                          PaperButton(
                            label: 'Crush all',
                            variant: PaperButtonVariant.danger,
                            compact: true,
                            onPressed: () => Navigator.pop(ctx, true),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(conversationsProvider.notifier)
                          .deleteAll();
                      ref.read(activeChatProvider.notifier).clear();
                      if (context.mounted) {
                        showPaperToast(context, 'Chat history deleted');
                      }
                    }
                  },
          ),
          const Divider(color: ScrapTheme.dividers),
          ListTile(
            title: Text('Gestures', style: ScrapTextStyles.body),
            subtitle: Text(
              'Configure shortcut edge motions',
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.mutedText,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: ScrapTheme.mutedText,
            ),
            onTap: () {
              ScrapFeedback.tap();
              context.push('/settings/gestures');
            },
          ),
          const Divider(color: ScrapTheme.dividers),
        ],
      ),
    );
  }
}
