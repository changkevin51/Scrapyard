import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/agent_models.dart';
import '../providers/agent_providers.dart';

class AgentCommandBar extends ConsumerWidget {
  const AgentCommandBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildPill(ref, AgentCommand.restructure, 'Restructure'),
          _buildPill(ref, AgentCommand.studyPlan, 'Study Plan'),
          _buildPill(ref, AgentCommand.webSearch, 'Web Search'),
          _buildPill(ref, AgentCommand.summarise, 'Summarise'),
          _buildPill(ref, AgentCommand.ask, 'Ask'),
        ],
      ),
    );
  }

  Widget _buildPill(WidgetRef ref, AgentCommand command, String label) {
    final active = ref.watch(activeAgentCommandProvider) == command;
    const bgColor = Color(0xFFEDEAE4); // Warm surface background
    
    return GestureDetector(
      onTap: () => ref.read(activeAgentCommandProvider.notifier).state = command,
      child: Container(
        margin: const EdgeInsets.only(right: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(3), // 3px radius pill
        ),
        child: Text(
          label,
          style: KotoTextStyles.caption.copyWith(
            color: active ? KotoTheme.accent : const Color(0xFF4A4A4A),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
