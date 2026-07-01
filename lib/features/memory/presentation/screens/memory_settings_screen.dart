import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/memory_providers.dart';
import '../../domain/models/memory_models.dart';

class MemorySettingsScreen extends ConsumerStatefulWidget {
  const MemorySettingsScreen({super.key});

  @override
  ConsumerState<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

class _MemorySettingsScreenState extends ConsumerState<MemorySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KotoTheme.background,
      appBar: AppBar(
        title: Text('Memory & Insights', style: KotoTextStyles.heading.copyWith(fontSize: 20)),
        backgroundColor: KotoTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: KotoTheme.primaryText),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
          _buildChartSection(),
          const Padding(
             padding: EdgeInsets.symmetric(vertical: 24.0),
             child: Divider(height: 1, color: KotoTheme.dividers),
          ),
          _buildAutoPatternsSection(),
          const Padding(
             padding: EdgeInsets.symmetric(vertical: 24.0),
             child: Divider(height: 1, color: KotoTheme.dividers),
          ),
          _buildUserRulesSection(),
          const Padding(
             padding: EdgeInsets.symmetric(vertical: 24.0),
             child: Divider(height: 1, color: KotoTheme.dividers),
          ),
          _buildSessionHistorySection(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title.toUpperCase(),
          style: KotoTextStyles.label.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.bold),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Study Stats (Last 7 Days)'),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.only(top: 16, right: 16),
          child: BarChart(
             BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 50,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                   show: true,
                   bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                         showTitles: true,
                         getTitlesWidget: (value, meta) {
                            const style = TextStyle(color: KotoTheme.mutedText, fontSize: 10);
                            Widget text;
                            switch (value.toInt()) {
                              case 0: text = const Text('M', style: style); break;
                              case 1: text = const Text('T', style: style); break;
                              case 2: text = const Text('W', style: style); break;
                              case 3: text = const Text('T', style: style); break;
                              case 4: text = const Text('F', style: style); break;
                              case 5: text = const Text('S', style: style); break;
                              case 6: text = const Text('S', style: style); break;
                              default: text = const Text('', style: style); break;
                            }
                            return Padding(padding: const EdgeInsets.only(top: 8), child: text);
                         },
                         reservedSize: 28,
                      ),
                   ),
                   leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                   topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                   rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                   show: true,
                   drawVerticalLine: false,
                   horizontalInterval: 10,
                   getDrawingHorizontalLine: (value) {
                      return const FlLine(color: KotoTheme.dividers, strokeWidth: 1);
                   },
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                   _makeBarData(0, 15),
                   _makeBarData(1, 28),
                   _makeBarData(2, 40),
                   _makeBarData(3, 10),
                   _makeBarData(4, 5),
                   _makeBarData(5, 30),
                   _makeBarData(6, 45),
                ],
             ),
          ),
        )
      ],
    );
  }

  BarChartGroupData _makeBarData(int x, double y) {
     return BarChartGroupData(
        x: x,
        barRods: [
           BarChartRodData(
              toY: y,
              color: KotoTheme.accent,
              width: 12,
              borderRadius: BorderRadius.circular(2),
           ),
        ],
     );
  }

  Widget _buildAutoPatternsSection() {
     final patternsAsync = ref.watch(autoPatternsProvider);
     
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           _buildSectionHeader(
              'Observed Patterns',
              trailing: GestureDetector(
                 onTap: () async {
                    await ref.read(memoryRepositoryProvider).clearAutoPatterns();
                    ref.invalidate(autoPatternsProvider);
                 },
                 child: Text('Clear', style: KotoTextStyles.caption.copyWith(color: KotoTheme.accent, fontWeight: FontWeight.bold)),
              )
           ),
           const SizedBox(height: 16),
           patternsAsync.when(
              loading: () => const Text('Loading...'),
              error: (err, stack) => Text('Error: $err'),
              data: (patterns) {
                 if (patterns.isEmpty) {
                    return Text('Koto is still observing your style. Studies need more time.', style: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText));
                 }
                 return Column(
                    children: patterns.map((p) => _buildPatternItem(p)).toList(),
                 );
              },
           )
        ],
     );
  }

  Widget _buildPatternItem(MemoryPattern pattern) {
     return Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
              Text(pattern.ruleJson, style: KotoTextStyles.body),
              const SizedBox(height: 8),
              Row(
                 children: [
                    Text('Confidence', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
                    const SizedBox(width: 8),
                    Expanded(
                       child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                             color: KotoTheme.dividers,
                             borderRadius: BorderRadius.circular(1.5),
                          ),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                             widthFactor: pattern.confidence,
                             child: Container(
                                decoration: BoxDecoration(
                                   color: KotoTheme.accent,
                                   borderRadius: BorderRadius.circular(1.5),
                                ),
                             ),
                          ),
                       )
                    )
                 ],
              )
           ],
        ),
     );
  }

  Widget _buildUserRulesSection() {
     final rulesAsync = ref.watch(userRulesProvider);
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           _buildSectionHeader('My Rules', trailing: const Icon(Icons.add, color: KotoTheme.accent, size: 20)),
           const SizedBox(height: 16),
           rulesAsync.when(
              loading: () => const Text('Loading...'),
              error: (err, stack) => Text('Error: $err'),
              data: (rules) {
                 if (rules.isEmpty) {
                    return Text('Add explicit rules to always override AI behaviour.', style: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText));
                 }
                 return Column(
                    children: rules.map((r) => ListTile(
                       contentPadding: EdgeInsets.zero,
                       title: Text(r.label, style: KotoTextStyles.heading.copyWith(fontSize: 16)),
                       subtitle: Text(r.instructionText, style: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText)),
                       trailing: Switch(
                          value: r.isActive,
                          onChanged: (val) {},
                          activeColor: KotoTheme.accent,
                       ),
                    )).toList(),
                 );
              },
           )
        ],
     );
  }

  Widget _buildSessionHistorySection() {
     final sessionsAsync = ref.watch(studySessionsProvider);
     return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           _buildSectionHeader('Session History'),
           const SizedBox(height: 16),
           sessionsAsync.when(
              loading: () => const Text('Loading...'),
              error: (err, stack) => Text('Error: $err'),
              data: (sessions) {
                 if (sessions.isEmpty) {
                    return Text('No sessions recorded yet.', style: KotoTextStyles.body.copyWith(color: KotoTheme.mutedText));
                 }
                 return Column(
                    children: sessions.map((s) {
                       final date = DateTime.fromMillisecondsSinceEpoch(s.startTime);
                       // Simplistic display
                       return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                             children: [
                                Text('${date.month}/${date.day} — ${s.totalQueries} actions', style: KotoTextStyles.body),
                                Text(s.documentIds.isEmpty ? 'No Docs' : '${s.documentIds.length} Docs', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
                             ],
                          ),
                       );
                    }).toList(),
                 );
              },
           )
        ],
     );
  }
}
