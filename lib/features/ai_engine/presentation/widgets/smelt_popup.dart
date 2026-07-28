import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/paper_button.dart';
import '../../../../core/widgets/paper_controls.dart';
import '../../../../core/widgets/paper_surfaces.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
import '../../../ai_chat/domain/models/gemini_model.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_chat/presentation/widgets/chat_suggestion_chips.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import '../providers/smelt_provider.dart';
import 'api_key_dialog.dart';
import 'latex_markdown_view.dart';

/// Popup widget that displays the smelt AI response
class SmeltPopup extends ConsumerStatefulWidget {
  final Rect selectionRect;
  final VoidCallback onDismiss;
  final VoidCallback onCollapse;
  final VoidCallback onTryAnotherModel;
  final Size screenSize;

  const SmeltPopup({
    super.key,
    required this.selectionRect,
    required this.onDismiss,
    required this.onCollapse,
    required this.onTryAnotherModel,
    required this.screenSize,
  });

  @override
  ConsumerState<SmeltPopup> createState() => SmeltPopupState();
}

class SmeltPopupState extends ConsumerState<SmeltPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _rotateAnim;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _rotateAnim = Tween<double>(begin: -1.2 * math.pi / 180, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  /// Reverse entrance animation, then notify the host to remove the overlay.
  Future<void> dismiss() async {
    if (_closing) return;
    _closing = true;
    await _animController.reverse();
    if (mounted) widget.onDismiss();
  }

  /// Hide the popup without clearing smelt state (e.g. while picking a model).
  Future<void> collapse() async {
    if (_closing) return;
    _closing = true;
    await _animController.reverse();
    if (mounted) widget.onCollapse();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Preferred popup width; grows for math, capped so it fits the screen.
  double _popupWidth() {
    const margin = 16.0;
    const preferred = 420.0;
    const maxWidth = 480.0;
    final available = widget.screenSize.width - (margin * 2);
    return math.min(maxWidth, math.min(preferred, available));
  }

  Offset _calculatePopupPosition() {
    final rect = widget.selectionRect;
    final screenSize = widget.screenSize;
    final popupWidth = _popupWidth();
    const popupMinHeight = 100.0;
    const margin = 16.0;

    // Try below the selection first
    double top = rect.bottom + 12;
    double left = rect.center.dx - popupWidth / 2;

    // If not enough space below, go above
    if (top + popupMinHeight > screenSize.height - margin) {
      top = rect.top - popupMinHeight - 12;
    }

    // Clamp to screen
    if (top < margin) top = margin;
    if (left < margin) left = margin;
    if (left + popupWidth > screenSize.width - margin) {
      left = screenSize.width - popupWidth - margin;
    }

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smeltProvider);
    final position = _calculatePopupPosition();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: _rotateAnim,
            builder: (context, child) => Transform.rotate(
              angle: _rotateAnim.value,
              alignment: Alignment.topCenter,
              child: child,
            ),
            child: TapRegion(
              onTapOutside: (_) => dismiss(),
              child: _buildCard(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(SmeltState state) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: _popupWidth(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: TornSheet(
            seed: 42,
            edges: const {TornEdge.bottom, TornEdge.right},
            amplitude: 3.5,
            grain: true,
            grainOpacity: 0.018,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TapeStrip(label: '⟨ Smelt ⟩', tiltDegrees: -1.5),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: _buildContent(state),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(SmeltState state) {
    if (state.isLoading) {
      return _SmeltLoadingRow(forceCodeExecution: state.forceCodeExecution);
    }
    if (state.error != null) {
      return _buildErrorState(state.error!);
    }
    if (state.response == null) {
      return const SizedBox();
    }
    return _buildResponseContent(
      state.response!,
      showSteps: state.showSteps,
      showCodeOutput: state.showCodeOutput,
    );
  }

  Widget _buildErrorState(String error) {
    final isMissingKey = error.contains(SmeltService.missingApiKeyMessage) ||
        error.contains('No Gemini API key');

    // Strip the "Exception: " prefix for display.
    final displayError = error.startsWith('Exception: ')
        ? error.substring('Exception: '.length)
        : error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: ScrapTheme.inkRed),
            const SizedBox(width: 8),
            Text(
              isMissingKey ? 'API key needed' : 'Error',
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.inkRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isMissingKey
              ? SmeltService.missingApiKeyMessage
              : displayError,
          style: ScrapTextStyles.caption.copyWith(color: ScrapTheme.secondaryText),
        ),
        if (isMissingKey) ...[
          const SizedBox(height: 12),
          PaperButton(
            label: 'Add key',
            variant: PaperButtonVariant.primary,
            torn: true,
            onPressed: () async {
              final saved = await showApiKeyDialog(context, allowSkip: false);
              if (saved == true && mounted) {
                ref.read(smeltProvider.notifier).startLoading();
                await ref.read(smeltProvider.notifier).retry();
              }
            },
          ),
        ] else ...[
          const SizedBox(height: 12),
          _buildTryAnotherModelButton(),
        ],
      ],
    );
  }

  Widget _buildResponseContent(
    SmeltResponse response, {
    required bool showSteps,
    required bool showCodeOutput,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (response.isMath) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ScrapTheme.accentSurface,
              borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            ),
            child: _buildMathAnswer(response.answer),
          ),
        ] else ...[
          SelectableText(
            response.answer,
            style: ScrapTextStyles.body.copyWith(fontSize: 15, height: 1.5),
          ),
        ],
        if (response.steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildExpandToggle(
            expanded: showSteps,
            expandedLabel: 'Hide steps',
            collapsedLabel: 'Show steps',
            onTap: () => ref.read(smeltProvider.notifier).toggleSteps(),
          ),
          if (showSteps) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ScrapTheme.codeSurface,
                borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              ),
              child: _buildMathSteps(response.steps),
            ),
          ],
        ],
        if (response.usedCodeExecution) ...[
          const SizedBox(height: 12),
          _buildExpandToggle(
            expanded: showCodeOutput,
            expandedLabel: 'Hide code',
            collapsedLabel: 'Show code',
            onTap: () => ref.read(smeltProvider.notifier).toggleCodeOutput(),
          ),
          if (showCodeOutput) ...[
            const SizedBox(height: 12),
            ...response.codeRuns.map(
              (run) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SmeltCodeRunView(run: run),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _buildChatHandoff(response),
        const SizedBox(height: 8),
        _buildFooter(response),
      ],
    );
  }

  Widget _buildExpandToggle({
    required bool expanded,
    required String expandedLabel,
    required String collapsedLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
          border: Border.all(color: ScrapTheme.dividers),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: ScrapTheme.mutedText,
            ),
            const SizedBox(width: 4),
            Text(
              expanded ? expandedLabel : collapsedLabel,
              style: ScrapTextStyles.caption.copyWith(
                color: ScrapTheme.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTryAnotherModelButton() {
    return PaperButton(
      label: 'Try another model',
      icon: Icons.swap_horiz,
      variant: PaperButtonVariant.ghost,
      compact: true,
      onPressed: widget.onTryAnotherModel,
    );
  }

  Widget _buildFooter(SmeltResponse response) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (response.modelFallbackNote != null) ...[
          Text(
            response.modelFallbackNote!,
            style: ScrapTextStyles.caption.copyWith(
              color: ScrapTheme.secondaryText,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            _buildTryAnotherModelButton(),
            const Spacer(),
            Text(
              'Powered by Gemini ${GeminiChatModel.displayLabel(response.modelUsed)}',
              style: ScrapTextStyles.stamp.copyWith(
                color: ScrapTheme.mutedText,
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openChat({String? autoSend}) {
    final smelt = ref.read(smeltProvider);
    final response = smelt.response;
    if (response == null) return;

    final noteId = ref.read(activeNoteIdProvider);
    final tabs = ref.read(openedTabsProvider);
    String? noteTitle;
    for (final t in tabs) {
      if (t.id == noteId) {
        noteTitle = t.title;
        break;
      }
    }

    ref.read(pendingChatSeedProvider.notifier).state = ChatSeed(
      smeltAnswer: response.answer,
      smeltSteps: response.steps,
      image: smelt.lastImageBytes,
      autoSend: autoSend,
      noteId: noteId,
      noteTitle: noteTitle,
    );
    ref.read(chatPanelOpenProvider.notifier).state = true;
    dismiss();
  }

  Widget _buildChatHandoff(SmeltResponse response) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (response.suggestions.isNotEmpty) ...[
          Text(
            'Ask next',
            style: ScrapTextStyles.stamp.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 8),
          ChatSuggestionChips(
            suggestions: response.suggestions,
            onSelected: (q) => _openChat(autoSend: q),
          ),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: () => _openChat(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Continue in chat',
                style: ScrapTextStyles.caption.copyWith(
                  color: ScrapTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 14, color: ScrapTheme.accent),
            ],
          ),
        ),
      ],
    );
  }

  /// Build math answer — uses the same delimiter-aware renderer as steps,
  /// because answers often look like `\(x=1\) or \(x=2\)` (not a single Math.tex blob).
  Widget _buildMathAnswer(String answer) {
    return LatexMarkdownView(
      text: answer,
      compact: true,
      baseStyle: ScrapTextStyles.body.copyWith(
        fontSize: 25,
        height: 1.1,
        color: ScrapTheme.accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Build math steps with LaTeX rendering
  Widget _buildMathSteps(String steps) {
    return LatexMarkdownView(text: steps);
  }
}

/// Loading row that swaps "Smelting..." → "Verifying with code..." after 1s
/// when forced code execution is requested.
class _SmeltLoadingRow extends StatefulWidget {
  final bool forceCodeExecution;

  const _SmeltLoadingRow({required this.forceCodeExecution});

  @override
  State<_SmeltLoadingRow> createState() => _SmeltLoadingRowState();
}

class _SmeltLoadingRowState extends State<_SmeltLoadingRow> {
  bool _showCodeMessage = false;

  @override
  void initState() {
    super.initState();
    _maybeSchedule();
  }

  @override
  void didUpdateWidget(covariant _SmeltLoadingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forceCodeExecution != widget.forceCodeExecution) {
      _showCodeMessage = false;
      _maybeSchedule();
    }
  }

  void _maybeSchedule() {
    if (!widget.forceCodeExecution) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !widget.forceCodeExecution) return;
      setState(() => _showCodeMessage = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.forceCodeExecution && _showCodeMessage
        ? 'Verifying with code...'
        : 'Smelting...';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const PaperDots(),
          const SizedBox(width: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              message,
              key: ValueKey(message),
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.mutedText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Styled code + output panel for a single Gemini code-execution run.
class _SmeltCodeRunView extends StatelessWidget {
  final SmeltCodeRun run;

  const _SmeltCodeRunView({required this.run});

  static TextStyle get _mono => ScrapTextStyles.stamp.copyWith(
        fontSize: 12,
        height: 1.45,
        letterSpacing: 0,
        fontWeight: FontWeight.w400,
        color: ScrapTheme.primaryText,
        decoration: TextDecoration.none,
      );

  @override
  Widget build(BuildContext context) {
    final lang = run.language.trim().isEmpty
        ? 'python'
        : run.language.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run.code.trim().isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2F2C29),
              borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              border: Border.all(color: ScrapTheme.kraft.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(ScrapTheme.borderRadiusDefault - 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.terminal, size: 13, color: Color(0xFFC9B8A4)),
                      const SizedBox(width: 6),
                      Text(
                        lang.toUpperCase(),
                        style: ScrapTextStyles.stamp.copyWith(
                          color: const Color(0xFFC9B8A4),
                          fontSize: 10,
                          letterSpacing: 1.0,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: SelectableText(
                    run.code.trimRight(),
                    style: _mono.copyWith(color: const Color(0xFFEDE6DC)),
                  ),
                ),
              ],
            ),
          ),
        if (run.output.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: ScrapTheme.accentSurface,
              borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              border: Border.all(color: ScrapTheme.dividers),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'Output',
                    style: ScrapTextStyles.stamp.copyWith(
                      color: ScrapTheme.accent,
                      fontSize: 10,
                      letterSpacing: 1.0,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: SelectableText(
                    run.output.trimRight(),
                    style: _mono.copyWith(color: ScrapTheme.bodyText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
