import 'package:flutter/material.dart';
import '../../../../core/theme/koto_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Example providers for settings
final languageDetectionProvider = StateProvider<bool>((ref) => true);
final nativeLanguageProvider = StateProvider<String>((ref) => 'English');
final enabledScriptsProvider = StateProvider<List<String>>((ref) => ['Japanese', 'Latin']);

class LanguageSettingsPanel extends ConsumerWidget {
  const LanguageSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detection = ref.watch(languageDetectionProvider);
    final nativeLang = ref.watch(nativeLanguageProvider);
    // Setting up the basic layout
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Language & Detection'),
        const SizedBox(height: 16),
        _buildToggle('Auto-detect Language', detection, (val) {
           ref.read(languageDetectionProvider.notifier).state = val;
        }),
        const SizedBox(height: 16),
        Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text('Native Language', style: KotoTextStyles.body),
             DropdownButton<String>(
                value: nativeLang,
                items: ['English', 'Spanish', 'French'].map((e) => DropdownMenuItem(value: e, child: Text(e, style: KotoTextStyles.body))).toList(),
                onChanged: (v) {
                   if (v != null) ref.read(nativeLanguageProvider.notifier).state = v;
                },
                underline: const SizedBox(),
             ),
           ],
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Detected Scripts'),
        const SizedBox(height: 16),
        _buildScriptToggle('Japanese', ref, true),
        _buildScriptToggle('Chinese', ref, false),
        _buildScriptToggle('Korean', ref, false),
      ],
    );
  }

  Widget _buildSectionHeader(String text) {
     return Text(
         text.toUpperCase(),
         style: KotoTextStyles.label.copyWith(
            color: KotoTheme.accent,
            fontWeight: FontWeight.bold,
         ),
     );
  }

  Widget _buildToggle(String title, bool current, Function(bool) onChanged) {
     return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           Text(title, style: KotoTextStyles.body),
           Switch(
              value: current,
              onChanged: onChanged,
              activeColor: KotoTheme.accent,
           ),
        ],
     );
  }

  Widget _buildScriptToggle(String script, WidgetRef ref, bool forcedEnabled) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 12.0),
       child: _buildToggle(script, forcedEnabled, (v) {}), // Placeholder logic
     );
  }
}
