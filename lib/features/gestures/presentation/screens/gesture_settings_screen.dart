import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../providers/gesture_providers.dart';

class GestureSettingsScreen extends ConsumerWidget {
  const GestureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: KotoTheme.background,
      appBar: AppBar(
        title: Text('Gestures', style: KotoTextStyles.heading.copyWith(fontSize: 20)),
        backgroundColor: KotoTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: KotoTheme.primaryText),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
           _buildSectionHeader('Screen Edges'),
           _buildToggleRow('Edge Swipes', ref.watch(edgeSwipesEnabledProvider), (val) {
             ref.read(edgeSwipesEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 8),
           Text('Left edge right: Document Navigator\nRight edge left: AI Agent Panel\nBottom edge up: Settings', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
           const Padding(
             padding: EdgeInsets.symmetric(vertical: 24.0),
             child: Divider(height: 1, color: KotoTheme.dividers),
           ),

           _buildSectionHeader('Multi-Touch & Tap Holds'),
           _buildToggleRow('Tap-Hold Expanding Scope', ref.watch(tapHoldExpandEnabledProvider), (val) {
             ref.read(tapHoldExpandEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 8),
           _buildToggleRow('Multi-Finger Actions', ref.watch(multiFingerEnabledProvider), (val) {
             ref.read(multiFingerEnabledProvider.notifier).state = val;
           }),
           const Padding(
             padding: EdgeInsets.symmetric(vertical: 24.0),
             child: Divider(height: 1, color: KotoTheme.dividers),
           ),

           _buildSectionHeader('Morse Action Corner'),
           _buildToggleRow('Enable Morse Input', ref.watch(morseEnabledProvider), (val) {
             ref.read(morseEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 16),
           Text('Bottom left corner, 52x52px zone.', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
           const SizedBox(height: 16),
           _buildMorseActionRow('· ·', 'AI Popup on last word'),
           _buildMorseActionRow('· —', 'Language Sidebar'),
           _buildMorseActionRow('— ·', 'Summarise Document'),
           _buildMorseActionRow('— —', 'AI Agent Panel'),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title.toUpperCase(),
        style: KotoTextStyles.label.copyWith(
           color: KotoTheme.accent,
           fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: KotoTextStyles.body),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: KotoTheme.accent,
        ),
      ],
    );
  }

  Widget _buildMorseActionRow(String pattern, String actionDesc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(pattern, style: KotoTextStyles.heading.copyWith(fontWeight: FontWeight.bold, color: KotoTheme.primaryText)),
          Text(actionDesc, style: KotoTextStyles.body.copyWith(color: KotoTheme.secondaryText)),
        ],
      ),
    );
  }
}
