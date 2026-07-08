import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/koto_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KotoTheme.background,
      appBar: AppBar(
        title: Text('Settings', style: KotoTextStyles.heading.copyWith(fontSize: 20)),
        backgroundColor: KotoTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: KotoTheme.primaryText),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        children: [
            ListTile(
              title: Text('Gestures', style: KotoTextStyles.body),
              subtitle: Text('Configure shortcut edge motions', style: KotoTextStyles.caption.copyWith(color: KotoTheme.mutedText)),
              trailing: const Icon(Icons.chevron_right, color: KotoTheme.mutedText),
              onTap: () => context.push('/settings/gestures'),
            ),
            const Divider(color: KotoTheme.dividers),
        ]
      )
    );
  }
}
