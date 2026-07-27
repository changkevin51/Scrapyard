import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../../ai_engine/data/smelt_service.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../ai_engine/presentation/widgets/api_key_dialog.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/gemini_model.dart';
import '../providers/chat_providers.dart';
import 'chat_history_sheet.dart';
import 'chat_message_bubble.dart';
import 'chat_suggestion_chips.dart';
import 'model_picker_sheet.dart';

/// Sliding right-side AI chat panel over the note editor.
class AiChatPanel extends ConsumerStatefulWidget {
  const AiChatPanel({super.key});

  @override
  ConsumerState<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends ConsumerState<AiChatPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ScrapMotion.panel);
    _slide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ScrapMotion.panelCurve));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _composer.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _syncOpen(bool open) {
    if (open) {
      if (_ctrl.status != AnimationStatus.completed &&
          _ctrl.status != AnimationStatus.forward) {
        _ctrl.forward();
      }
    } else {
      if (_ctrl.status != AnimationStatus.dismissed &&
          _ctrl.status != AnimationStatus.reverse) {
        _ctrl.reverse();
      }
    }
  }

  Future<void> _handlePendingSeed() async {
    final seed = ref.read(pendingChatSeedProvider);
    if (seed == null) return;
    ref.read(pendingChatSeedProvider.notifier).state = null;
    await ref.read(activeChatProvider.notifier).consumeSeed(seed);
  }

  void _close() {
    ref.read(chatPanelOpenProvider.notifier).state = false;
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _composer.text).trim();
    final attachment = override == null
        ? ref.read(pendingChatAttachmentProvider)
        : null;
    if (text.isEmpty && attachment == null) return;
    ScrapFeedback.action();
    if (override == null) {
      _composer.clear();
      if (attachment != null) {
        ref.read(pendingChatAttachmentProvider.notifier).state = null;
      }
    }
    await ref
        .read(activeChatProvider.notifier)
        .send(text, imageBytes: attachment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _requestCanvasCapture() {
    _focusNode.unfocus();
    ref.read(chatCaptureRequestProvider.notifier).state = true;
    ref.read(chatPanelOpenProvider.notifier).state = false;
  }

  void _clearAttachment() {
    ref.read(pendingChatAttachmentProvider.notifier).state = null;
  }

  bool get _isDesktop {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(chatPanelOpenProvider);
    _syncOpen(open);

    ref.listen(chatPanelOpenProvider, (prev, next) {
      if (next == true && prev != true) {
        _handlePendingSeed();
      }
    });

    // Also consume seed if panel was already open when seed was set
    ref.listen(pendingChatSeedProvider, (prev, next) {
      if (next != null && ref.read(chatPanelOpenProvider)) {
        _handlePendingSeed();
      }
    });

    final widthPref = ref.watch(chatPanelWidthProvider);
    final screenW = MediaQuery.of(context).size.width;
    final panelW = math.min(widthPref, screenW * 0.92).clamp(280.0, 560.0);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        if (_ctrl.value == 0 && !open) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            // Scrim
            Positioned.fill(
              child: GestureDetector(
                onTap: _close,
                child: Opacity(
                  opacity: 0.35 * _ctrl.value,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
            // Panel
            Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: _slide,
                child: SizedBox(
                  width: panelW,
                  height: double.infinity,
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: _buildPanel(panelW),
    );
  }

  Widget _buildPanel(double panelW) {
    final chat = ref.watch(activeChatProvider);
    final modelId = ref.watch(chatModelProvider);
    final modelLabel = GeminiChatModel.displayLabel(modelId);
    final apiKey = ref.watch(apiKeyProvider).valueOrNull;
    final hasKey = apiKey != null && apiKey.isNotEmpty;
    final visible = chat.visibleMessages;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TornSheet(
            seed: 17,
            edges: const {TornEdge.left},
            amplitude: 5.5,
            grain: true,
            grainOpacity: 0.018,
            child: Column(
              children: [
                _buildHeader(modelLabel),
                const Divider(height: 1, color: ScrapTheme.dividers),
                Expanded(
                  child: !hasKey
                      ? _buildNoKeyState()
                      : visible.isEmpty && !chat.isStreaming
                          ? _buildEmptyState()
                          : _buildMessageList(chat, visible),
                ),
                if (hasKey) _buildComposer(chat.isStreaming),
              ],
            ),
          ),
          // Drag handle for resize — sits on the torn edge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 14,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                final next = panelW - d.delta.dx;
                ref.read(chatPanelWidthProvider.notifier).setWidth(next);
              },
              child: const MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String modelLabel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Column(
        children: [
          const TapeStrip(
            label: '⟨ Ask ⟩',
            tiltDegrees: -1.2,
            margin: EdgeInsets.only(bottom: 10),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => showModelPickerSheet(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ScrapTheme.accentSurface,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: ScrapTheme.dividers),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        modelLabel,
                        style: ScrapTextStyles.caption.copyWith(
                          fontSize: 11,
                          color: ScrapTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.expand_more,
                          size: 14, color: ScrapTheme.accent),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              PaperIconButton(
                icon: Icons.history,
                tooltip: 'History',
                color: ScrapTheme.secondaryText,
                onPressed: () {
                  showChatHistorySheet(
                    context,
                    onOpen: (c) {
                      ref
                          .read(activeChatProvider.notifier)
                          .openConversation(c.id);
                    },
                  );
                },
              ),
              PaperIconButton(
                icon: Icons.add,
                tooltip: 'New chat',
                iconSize: 22,
                color: ScrapTheme.secondaryText,
                onPressed: () {
                  final noteId = ref.read(activeNoteIdProvider);
                  final tabs = ref.read(openedTabsProvider);
                  String? title;
                  for (final t in tabs) {
                    if (t.id == noteId) {
                      title = t.title;
                      break;
                    }
                  }
                  ref.read(activeChatProvider.notifier).newChat(
                        noteId: noteId,
                        noteTitle: title,
                      );
                },
              ),
              PaperIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                color: ScrapTheme.mutedText,
                onPressed: _close,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoKeyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              SmeltService.missingApiKeyMessage,
              textAlign: TextAlign.center,
              style: ScrapTextStyles.body.copyWith(color: ScrapTheme.bodyText),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => showApiKeyDialog(context, allowSkip: false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: ScrapTheme.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Add API key',
                  style: ScrapTextStyles.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ask anything about your notes',
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.secondaryText,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ChatSuggestionChips(
              suggestions: const [
                'Explain my notes',
                'Quiz me',
                'Summarize this page',
              ],
              onSelected: (s) => _send(s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(ChatState chat, List<ChatMessage> visible) {
    // Reverse list so newest is at bottom visually with reverse:true
    final items = visible.reversed.toList();
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      itemCount: items.length + (chat.isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (chat.isStreaming && index == 0) {
          // Streaming bubble — no entrance (updates every token).
          return ChatMessageBubble(
            message: ChatMessage(
              id: 'streaming',
              conversationId: chat.conversation?.id ?? '',
              role: ChatRole.assistant,
              content: chat.streamingText,
              createdAt: DateTime.now(),
            ),
            isStreaming: true,
            streamingOverride: chat.streamingText.isEmpty
                ? '…'
                : chat.streamingText,
          );
        }
        final msgIndex = chat.isStreaming ? index - 1 : index;
        final msg = items[msgIndex];
        return ScrapCardEntrance(
          key: ValueKey(msg.id),
          index: 0,
          stagger: Duration.zero,
          child: ChatMessageBubble(
            message: msg,
            onSuggestionTap: (s) => _send(s),
          ),
        );
      },
    );
  }

  Widget _buildComposer(bool isStreaming) {
    final attachment = ref.watch(pendingChatAttachmentProvider);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ScrapTheme.dividers)),
          color: ScrapTheme.cardSurface,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null) ...[
              _AttachmentChip(
                bytes: attachment,
                onClear: _clearAttachment,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: isStreaming ? null : _requestCanvasCapture,
                  child: AnimatedContainer(
                    duration: ScrapMotion.fast,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ScrapTheme.codeSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ScrapTheme.dividers),
                    ),
                    child: Icon(
                      Icons.crop_free,
                      color: isStreaming
                          ? ScrapTheme.mutedText
                          : ScrapTheme.secondaryText,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: ScrapTheme.codeSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ScrapTheme.dividers),
                    ),
                    child: KeyboardListener(
                      focusNode: _keyboardFocus,
                      onKeyEvent: (event) {
                        if (!_isDesktop) return;
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _send();
                        }
                      },
                      child: TextField(
                        controller: _composer,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: _isDesktop
                            ? TextInputAction.send
                            : TextInputAction.newline,
                        onSubmitted: _isDesktop ? (_) => _send() : null,
                        style: ScrapTextStyles.body.copyWith(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: attachment != null
                              ? 'Ask about this selection…'
                              : 'Ask a question…',
                          hintStyle: ScrapTextStyles.body.copyWith(
                            color: ScrapTheme.mutedText,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ScrapPressable(
                  scale: 0.9,
                  onTap: isStreaming
                      ? () => ref.read(activeChatProvider.notifier).stop()
                      : () => _send(),
                  child: AnimatedContainer(
                    duration: ScrapMotion.fast,
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ScrapTheme.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isStreaming ? Icons.stop_rounded : Icons.arrow_upward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onClear;

  const _AttachmentChip({required this.bytes, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ScrapTheme.dividers),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: 56,
            height: 56,
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onClear,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: ScrapTheme.secondaryText,
                shape: BoxShape.circle,
                border: Border.all(color: ScrapTheme.cardSurface, width: 1.5),
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
