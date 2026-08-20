import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../providers/gesture_providers.dart';

class GestureSettingsScreen extends ConsumerWidget {
  const GestureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ScrapTheme.background,
      appBar: AppBar(
        title: Text('Gestures', style: ScrapTextStyles.heading.copyWith(fontSize: 20)),
        backgroundColor: ScrapTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: ScrapTheme.primaryText),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
           _buildSectionHeader('Canvas'),
           _buildToggleRow('Two-Finger Tap to Undo', ref.watch(twoFingerTapUndoEnabledProvider), (val) {
             ref.read(twoFingerTapUndoEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 8),
           Text(
             'Quickly tap with two fingers to undo.',
             style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
           ),
           const SizedBox(height: 16),
           _buildToggleRow('Three-Finger Tap to Redo', ref.watch(threeFingerTapRedoEnabledProvider), (val) {
             ref.read(threeFingerTapRedoEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 8),
           Text(
             'Quickly tap with three fingers to redo.',
             style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
           ),
           const SizedBox(height: 16),
           _buildToggleRow('S Pen Button Eraser', ref.watch(sPenButtonEraserEnabledProvider), (val) {
             ref.read(sPenButtonEraserEnabledProvider.notifier).state = val;
           }),
           const SizedBox(height: 8),
           Text(
             'Hold the stylus side button to erase; release to return to your previous tool.',
             style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.mutedText),
           ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title.toUpperCase(),
        style: ScrapTextStyles.label.copyWith(
           color: ScrapTheme.accent,
           fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: ScrapTextStyles.body),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: ScrapTheme.accent,
        ),
      ],
    );
  }

}
