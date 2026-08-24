import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/scrap_overlays.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/scrap_tilt.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../data/feedback_service.dart';

Future<bool?> showFeedbackDialog(BuildContext context) {
  return showScrapDialog<bool>(
    context: context,
    builder: (context) => const FeedbackDialog(),
  );
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _service = FeedbackService();
  late final TextEditingController _message;
  late final TextEditingController _email;
  FeedbackKind _kind = FeedbackKind.idea;
  bool _sending = false;
  bool _sent = false;
  FeedbackResult? _error;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController();
    _email = TextEditingController();
    _message.addListener(() {
      if (_error != null) {
        setState(() => _error = null);
      } else {
        setState(() {});
      }
    });
    _email.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _canSend {
    final text = _message.text.trim();
    return !_sending &&
        !_sent &&
        text.length >= kFeedbackMinMessageLength &&
        text.length <= kFeedbackMaxMessageLength;
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final result = await _service.send(
      kind: _kind,
      message: _message.text,
      email: _email.text,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _sending = false;
        _error = result;
      });
      return;
    }

    setState(() {
      _sending = false;
      _sent = true;
    });
    _closeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  void _close([bool sent = false]) {
    _closeTimer?.cancel();
    Navigator.of(context).pop(sent || _sent);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: TornSheet(
          seed: 17,
          edges: const {TornEdge.bottom},
          amplitude: 4,
          grain: true,
          grainOpacity: 0.015,
          child: AnimatedSize(
            duration: ScrapMotion.panel,
            curve: ScrapMotion.panelCurve,
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
                child: _sent ? _buildThanks() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TapeStrip(label: '⟨ beta ⟩'),
        const SizedBox(height: 8),
        Text(
          'Send a scrap of feedback',
          style: ScrapTextStyles.heading.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          'Bugs, ideas, or whatever is stuck. We read every scrap.',
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.secondaryText,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kind in FeedbackKind.values)
              _KindChip(
                label: kind.label,
                selected: _kind == kind,
                onTap: _sending
                    ? null
                    : () {
                        ScrapFeedback.tap();
                        setState(() {
                          _kind = kind;
                          _error = null;
                        });
                      },
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _message,
          enabled: !_sending,
          minLines: 4,
          maxLines: 8,
          maxLength: kFeedbackMaxMessageLength,
          textCapitalization: TextCapitalization.sentences,
          style: ScrapTextStyles.body.copyWith(fontSize: 15),
          decoration: _fieldDecoration(
            hint: "What's working? What's stuck?",
          ).copyWith(
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: ScrapTextStyles.body.copyWith(fontSize: 14),
          decoration: _fieldDecoration(
            hint: 'Email (If you want a reply)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorStrip(message: _error!.message),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            if (_sending)
              const PaperDots()
            else
              PaperButton(
                label: 'Send',
                variant: PaperButtonVariant.primary,
                torn: true,
                onPressed: _canSend ? _send : null,
              ),
            const Spacer(),
            PaperButton(
              label: 'Cancel',
              variant: PaperButtonVariant.ghost,
              compact: true,
              onPressed: _sending ? null : _close,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Sending posts this message, the kind you picked, optional email, and app/device info. Notes and your Gemini key stay on this device.',
          style: ScrapTextStyles.caption.copyWith(
            color: ScrapTheme.mutedText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildThanks() {
    return _ThanksBody(onDone: () => _close(true));
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: ScrapTextStyles.caption.copyWith(
        color: ScrapTheme.mutedText,
      ),
      filled: true,
      fillColor: ScrapTheme.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        borderSide: const BorderSide(color: ScrapTheme.dividers),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        borderSide: const BorderSide(
          color: ScrapTheme.accent,
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
        borderSide: const BorderSide(color: ScrapTheme.dividers),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _KindChip({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScrapPressable(
      scale: 0.96,
      onTap: onTap,
      child: AnimatedContainer(
        duration: ScrapMotion.press,
        curve: ScrapMotion.pressCurve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? ScrapTheme.accentSurface : ScrapTheme.tape,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected
                ? ScrapTheme.accent.withValues(alpha: 0.45)
                : ScrapTheme.kraft.withValues(alpha: 0.85),
          ),
        ),
        child: Text(
          label,
          style: ScrapTextStyles.caption.copyWith(
            color: selected ? ScrapTheme.accent : ScrapTheme.secondaryText,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  final String message;

  const _ErrorStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ScrapTheme.inkRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            size: 18,
            color: ScrapTheme.inkRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.inkRed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanksBody extends StatefulWidget {
  final VoidCallback onDone;

  const _ThanksBody({required this.onDone});

  @override
  State<_ThanksBody> createState() => _ThanksBodyState();
}

class _ThanksBodyState extends State<_ThanksBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<Offset> _stampSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );
    _scale = Tween<double>(begin: 0.62, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _stampSlide = Tween<Offset>(
      begin: const Offset(0.08, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const TapeStrip(label: '⟨ beta ⟩'),
        const SizedBox(height: 20),
        ScaleTransition(
          scale: _scale,
          child: ScrapTilt(
            seed: 11,
            maxDegrees: 9,
            child: Image.asset(
              'assets/images/SplashLogo.png',
              width: 88,
              height: 88,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SlideTransition(
          position: _stampSlide,
          child: const ScrapStampLabel(
            text: '⟨ mailed ⟩',
            tiltDegrees: -3,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Thanks — we'll read this scrap.",
          textAlign: TextAlign.center,
          style: ScrapTextStyles.heading.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 20),
        PaperButton(
          label: 'Done',
          variant: PaperButtonVariant.primary,
          torn: true,
          onPressed: widget.onDone,
        ),
      ],
    );
  }
}
