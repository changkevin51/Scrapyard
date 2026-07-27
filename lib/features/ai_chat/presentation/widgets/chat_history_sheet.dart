import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../domain/models/chat_conversation.dart';
import '../providers/chat_providers.dart';

Future<void> showChatHistorySheet(
  BuildContext context, {
  void Function(ChatConversation conv)? onOpen,
}) {
  return showScrapSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: ScrapTheme.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ScrapTheme.borderRadiusDefault),
      ),
    ),
    builder: (_) => ChatHistorySheet(onOpen: onOpen),
  );
}

class ChatHistorySheet extends ConsumerWidget {
  final void Function(ChatConversation conv)? onOpen;

  const ChatHistorySheet({super.key, this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);
    final height = MediaQuery.of(context).size.height * 0.65;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
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
            const ScrapStampLabel(text: '⟨ Chats ⟩'),
            const SizedBox(height: 8),
            Text(
              'Chat History',
              style: ScrapTextStyles.heading.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: async.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: ScrapTheme.accent),
                ),
                error: (e, _) => Text(
                  'Could not load history: $e',
                  style: ScrapTextStyles.caption
                      .copyWith(color: Colors.redAccent),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Text(
                        'No chats yet',
                        style: ScrapTextStyles.body
                            .copyWith(color: ScrapTheme.mutedText),
                      ),
                    );
                  }
                  final groups = _group(list);
                  return ListView(
                    children: [
                      for (final entry in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: ScrapTextStyles.stamp.copyWith(fontSize: 10),
                          ),
                        ),
                        ...entry.value.map(
                          (c) => _HistoryTile(
                            conversation: c,
                            onTap: () {
                              Navigator.pop(context);
                              onOpen?.call(c);
                            },
                            onDelete: () async {
                              await ref
                                  .read(conversationsProvider.notifier)
                                  .delete(c.id);
                              final active = ref.read(activeChatProvider);
                              if (active.conversation?.id == c.id) {
                                ref.read(activeChatProvider.notifier).clear();
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, List<ChatConversation>> _group(List<ChatConversation> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final result = <String, List<ChatConversation>>{
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };
    for (final c in list) {
      final d = DateTime(c.updatedAt.year, c.updatedAt.month, c.updatedAt.day);
      if (d == today) {
        result['Today']!.add(c);
      } else if (d == yesterday) {
        result['Yesterday']!.add(c);
      } else {
        result['Earlier']!.add(c);
      }
    }
    result.removeWhere((_, v) => v.isEmpty);
    return result;
  }
}

class _HistoryTile extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.redAccent.withValues(alpha: 0.15),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      confirmDismiss: (_) async {
        ScrapFeedback.warn();
        return await showScrapDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: ScrapTheme.cardSurface,
                title: Text('Delete chat?', style: ScrapTextStyles.heading),
                content: Text(
                  'This conversation will be crushed.',
                  style: ScrapTextStyles.body,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel',
                        style: ScrapTextStyles.body
                            .copyWith(color: ScrapTheme.mutedText)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Crush',
                        style: ScrapTextStyles.body
                            .copyWith(color: Colors.redAccent)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: ScrapPressable(
        scale: 0.98,
        onTap: () {
          ScrapFeedback.tap();
          onTap();
        },
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: null,
        title: Text(
          conversation.title,
          style: ScrapTextStyles.body.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: conversation.noteTitle != null
            ? Text(
                'from ${conversation.noteTitle}',
                style: ScrapTextStyles.caption
                    .copyWith(color: ScrapTheme.mutedText),
              )
            : null,
        trailing: Text(
          _formatTime(conversation.updatedAt),
          style:
              ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
        ),
      ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
