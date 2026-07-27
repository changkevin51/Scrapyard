import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/scrapyard_theme.dart';
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

    return Scaffold(
      backgroundColor: ScrapTheme.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: ScrapTextStyles.heading.copyWith(fontSize: 20),
        ),
        backgroundColor: ScrapTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: ScrapTheme.primaryText),
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
              final saved = await showApiKeyDialog(context, allowSkip: false);
              if (saved == true && context.mounted) {
                final nowHasKey =
                    (ref.read(apiKeyProvider).valueOrNull ?? '').isNotEmpty;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      nowHasKey
                          ? (hasKey ? 'API key updated' : 'API key saved')
                          : 'API key removed',
                      style: ScrapTextStyles.body.copyWith(color: Colors.white),
                    ),
                    backgroundColor: ScrapTheme.accent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
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
            onTap: () => context.push('/settings/gestures'),
          ),
          const Divider(color: ScrapTheme.dividers),
        ],
      ),
    );
  }
}
