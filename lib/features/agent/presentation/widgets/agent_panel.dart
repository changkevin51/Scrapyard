import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/agent_providers.dart';
import '../../domain/models/agent_models.dart';
import 'agent_command_bar.dart';

class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key});

  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<AgentPanel> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  void _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    ref.read(agentConversationProvider.notifier).update((state) => [...state, ConversationMessage(text: text, isUser: true)]);
    _textController.clear();
    setState(() => _isLoading = true);
    _scrollToBottom();

    try {
      final service = ref.read(agentServiceProvider);
      final command = ref.read(activeAgentCommandProvider);
      String response = '';
      
      switch(command) {
        case AgentCommand.ask:
          response = await service.askAnything(text, 'Current Context placeholder');
          break;
        case AgentCommand.restructure:
          final res = await service.restructureText(text);
          response = 'Restructure Complete.\\nProposed:\\n${res.proposed}';
          break;
        case AgentCommand.studyPlan:
          final res = await service.createStudyPlan(text);
          response = 'Created Study Plan: ${res.title}\\nEstimated Hours: ${res.estimatedHours}\\nTopics: ${res.topics.length}';
          break;
        case AgentCommand.webSearch:
          response = await service.searchAndSummarize(text);
          break;
        case AgentCommand.summarise:
          response = await service.summarizePdf(text);
          break;
      }
      
      if (mounted) {
         ref.read(agentConversationProvider.notifier).update((state) => [...state, ConversationMessage(text: response, isUser: false)]);
      }
    } catch (e) {
      if (mounted) {
         ref.read(agentConversationProvider.notifier).update((state) => [...state, ConversationMessage(text: 'Error connecting to Agent: $e', isUser: false)]);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
         _scrollController.animateTo(
           _scrollController.position.maxScrollExtent,
           duration: const Duration(milliseconds: 300),
           curve: Curves.easeOut,
         );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(showAgentPanelProvider);
    if (!show) return const SizedBox.shrink();

    final messages = ref.watch(agentConversationProvider);

    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 376,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: KotoTheme.dividers, width: 1.0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
               padding: const EdgeInsets.only(left: 24, right: 24, top: 48), // Added top padding for safearea
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text(
                           'Scrapyard AI',
                           style: KotoTextStyles.heading.copyWith(color: const Color(0xFF4A4A4A), fontSize: 18),
                         ),
                         IconButton(
                           icon: const Icon(Icons.close, size: 20, color: KotoTheme.mutedText),
                           onPressed: () => ref.read(showAgentPanelProvider.notifier).state = false,
                           padding: EdgeInsets.zero,
                           constraints: const BoxConstraints(),
                         )
                      ]
                   ),
                   const SizedBox(height: 8),
                   Container(height: 2, color: KotoTheme.accent), // 2px brown line
                   const SizedBox(height: 16),
                   const AgentCommandBar(),
                 ],
               ),
            ),
            
            // Conversation Area
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(24),
                itemCount: messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == messages.length && _isLoading) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Agent is typing...', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText, fontStyle: FontStyle.italic)),
                    );
                  }
                  final msg = messages[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                         Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                               color: msg.isUser ? const Color(0xFFEDEAE4) : Colors.transparent,
                               borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                               msg.text,
                               style: KotoTextStyles.body.copyWith(
                                  color: KotoTheme.primaryText,
                               ),
                            ),
                         ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Autocomplete Field
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: KotoTheme.dividers)),
              ),
              child: TextField(
                controller: _textController,
                maxLines: 5,
                minLines: 1,
                style: KotoTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Ask Scrapyard AI...',
                  hintStyle: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send, color: KotoTheme.accent, size: 20),
                    onPressed: _submit,
                  )
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
