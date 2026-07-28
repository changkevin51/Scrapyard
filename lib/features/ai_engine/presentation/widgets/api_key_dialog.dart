import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
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
  return showScrapDialog<bool>(
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
  late final FocusNode _keyFocusNode;
  final _keyFieldKey = GlobalKey();
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
    _keyFocusNode = FocusNode();
    _keyFocusNode.addListener(_scrollKeyFieldIntoView);
    _controller.addListener(() {
      if (_testResult != null) {
        setState(() => _testResult = null);
      } else {
        setState(() {});
      }
    });
  }

  void _scrollKeyFieldIntoView() {
    if (!_keyFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = _keyFieldKey.currentContext;
      if (fieldContext == null || !mounted) return;
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _keyFocusNode.removeListener(_scrollKeyFieldIntoView);
    _keyFocusNode.dispose();
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

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        child: TornSheet(
          seed: 31,
          edges: const {TornEdge.bottom},
          amplitude: 4,
          grain: true,
          grainOpacity: 0.015,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TapeStrip(label: '⟨ Gemini ⟩'),
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
              KeyedSubtree(
                key: _keyFieldKey,
                child: TextField(
                controller: _controller,
                focusNode: _keyFocusNode,
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
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                _buildResultStrip(_testResult!),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_testing)
                    const PaperDots()
                  else
                    PaperButton(
                      label: 'Test connection',
                      variant: PaperButtonVariant.secondary,
                      onPressed: (_controller.text.trim().isEmpty || busy)
                          ? null
                          : _test,
                    ),
                  const SizedBox(width: 10),
                  if (_saving)
                    const PaperDots()
                  else
                    PaperButton(
                      label: 'Save',
                      variant: PaperButtonVariant.primary,
                      torn: true,
                      onPressed: canSave ? _save : null,
                    ),
                  const Spacer(),
                  if (_hasExistingKey)
                    PaperButton(
                      label: 'Remove key',
                      variant: PaperButtonVariant.danger,
                      compact: true,
                      onPressed: busy ? null : _remove,
                    ),
                  PaperButton(
                    label: widget.allowSkip ? 'Not now' : 'Cancel',
                    variant: PaperButtonVariant.ghost,
                    compact: true,
                    onPressed: busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
                ],
              ),
            ),
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
                    PaperButton(
                      label: _linkCopiedHint ?? 'Copy link',
                      variant: PaperButtonVariant.ghost,
                      compact: true,
                      onPressed: _copyLink,
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
            borderRadius: BorderRadius.circular(2),
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
    final color = ok ? ScrapTheme.accent : ScrapTheme.inkRed;
    final bg = ok
        ? ScrapTheme.accent.withValues(alpha: 0.08)
        : ScrapTheme.inkRed.withValues(alpha: 0.08);

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
