import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../data/api_key_service.dart';
import '../providers/smelt_provider.dart';

const _aiStudioUrl = 'https://aistudio.google.com/app/apikey';

/// Shows the Gemini API key setup dialog.
///
/// [allowSkip] controls the dismiss label: "Not now" for first-run,
/// "Cancel" when opened from Settings.
Future<bool?> showApiKeyDialog(
  BuildContext context, {
  bool allowSkip = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: allowSkip,
    builder: (context) => ApiKeyDialog(allowSkip: allowSkip),
  );
}

class ApiKeyDialog extends ConsumerStatefulWidget {
  final bool allowSkip;

  const ApiKeyDialog({super.key, this.allowSkip = true});

  @override
  ConsumerState<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends ConsumerState<ApiKeyDialog> {
  late final TextEditingController _controller;
  bool _obscure = true;
  bool _testing = false;
  bool _saving = false;
  ApiKeyTestResult? _testResult;
  String? _linkCopiedHint;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(apiKeyProvider).valueOrNull;
    _controller = TextEditingController(text: existing ?? '');
    _controller.addListener(() {
      if (_testResult != null) {
        setState(() => _testResult = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasExistingKey {
    final key = ref.read(apiKeyProvider).valueOrNull;
    return key != null && key.isNotEmpty;
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: _aiStudioUrl));
    setState(() => _linkCopiedHint = 'Link copied');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted && _linkCopiedHint == 'Link copied') {
      setState(() => _linkCopiedHint = null);
    }
  }

  Future<void> _test() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final result = await ref.read(apiKeyProvider.notifier).test(key);
    if (!mounted) return;

    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(apiKeyProvider.notifier).save(key);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testResult = const ApiKeyTestResult(
          success: false,
          message: 'Could not save the key. Try again.',
        );
      });
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiKeyProvider.notifier).clear();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _testResult = const ApiKeyTestResult(
          success: false,
          message: 'Could not remove the key. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _testing || _saving;
    final canSave = _controller.text.trim().isNotEmpty && !busy;

    return Dialog(
      backgroundColor: ScrapTheme.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: ScrapTheme.cardSurface,
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
          boxShadow: ScrapTheme.subtleShadow,
        ),
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⟨ Gemini ⟩',
                style: ScrapTextStyles.label.copyWith(
                  color: ScrapTheme.accent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Connect your AI key',
                style: ScrapTextStyles.heading.copyWith(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Scrapyard uses your own free Google AI Studio key, so Smelt costs nothing.',
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.secondaryText,
                ),
              ),
              const SizedBox(height: 20),
              _buildInstructions(),
              const SizedBox(height: 20),
              Text(
                'API key',
                style: ScrapTextStyles.label.copyWith(
                  color: ScrapTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                enabled: !busy,
                style: ScrapTextStyles.body.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  letterSpacing: 0.4,
                ),
                decoration: InputDecoration(
                  hintText: 'AQ.Ab...',
                  hintStyle: ScrapTextStyles.caption.copyWith(
                    color: ScrapTheme.mutedText,
                    fontFamily: 'monospace',
                  ),
                  filled: true,
                  fillColor: ScrapTheme.background,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show key' : 'Hide key',
                    onPressed: busy
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: ScrapTheme.mutedText,
                      size: 20,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ScrapTheme.borderRadiusDefault,
                    ),
                    borderSide: const BorderSide(color: ScrapTheme.dividers),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ScrapTheme.borderRadiusDefault,
                    ),
                    borderSide: const BorderSide(
                      color: ScrapTheme.accent,
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      ScrapTheme.borderRadiusDefault,
                    ),
                    borderSide: const BorderSide(color: ScrapTheme.dividers),
                  ),
                ),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                _buildResultStrip(_testResult!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: (_controller.text.trim().isEmpty || busy)
                        ? null
                        : _test,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ScrapTheme.accent,
                      side: BorderSide(
                        color: (_controller.text.trim().isEmpty || busy)
                            ? ScrapTheme.dividers
                            : ScrapTheme.accent,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ScrapTheme.borderRadiusDefault,
                        ),
                      ),
                    ),
                    child: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ScrapTheme.accent,
                            ),
                          )
                        : Text(
                            'Test connection',
                            style: ScrapTextStyles.body.copyWith(
                              color: ScrapTheme.accent,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: ScrapTheme.accent,
                      disabledBackgroundColor:
                          ScrapTheme.accent.withValues(alpha: 0.35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          ScrapTheme.borderRadiusDefault,
                        ),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Save',
                            style: ScrapTextStyles.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                  ),
                  const Spacer(),
                  if (_hasExistingKey)
                    TextButton(
                      onPressed: busy ? null : _remove,
                      child: Text(
                        'Remove key',
                        style: ScrapTextStyles.caption.copyWith(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      widget.allowSkip ? 'Not now' : 'Cancel',
                      style: ScrapTextStyles.caption.copyWith(
                        color: ScrapTheme.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ScrapTheme.accentSurface,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _step(
            '1',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open Google AI Studio',
                  style: ScrapTextStyles.body.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _aiStudioUrl,
                        style: ScrapTextStyles.caption.copyWith(
                          color: ScrapTheme.accent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _copyLink,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _linkCopiedHint ?? 'Copy link',
                        style: ScrapTextStyles.label.copyWith(
                          color: ScrapTheme.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _step(
            '2',
            Text(
              'Sign in with your Google account.',
              style: ScrapTextStyles.body.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          _step(
            '3',
            Text(
              'Tap “Create API key” and pick or create a project.',
              style: ScrapTextStyles.body.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
          _step(
            '4',
            Text(
              'Copy the key (it starts with "AQ.") and paste it below.',
              style: ScrapTextStyles.body.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'The free tier is enough for normal use. Your key stays on this device only.',
            style: ScrapTextStyles.caption.copyWith(
              color: ScrapTheme.mutedText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String number, Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ScrapTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            number,
            style: ScrapTextStyles.label.copyWith(
              color: ScrapTheme.accent,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildResultStrip(ApiKeyTestResult result) {
    final ok = result.success;
    final color = ok ? ScrapTheme.accent : Colors.redAccent;
    final bg = ok
        ? ScrapTheme.accent.withValues(alpha: 0.08)
        : Colors.redAccent.withValues(alpha: 0.08);

    final detail = ok && result.modelReply != null && result.modelReply!.isNotEmpty
        ? '${result.message} Model said: “${result.modelReply}”'
        : result.message;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: ScrapTextStyles.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
