import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../../core/widgets/torn_edge_clipper.dart';
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
  final Size screenSize;

  const SmeltPopup({
    super.key,
    required this.selectionRect,
    required this.onDismiss,
    required this.screenSize,
  });

  @override
  ConsumerState<SmeltPopup> createState() => _SmeltPopupState();
}

class _SmeltPopupState extends ConsumerState<SmeltPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _rotateAnim;

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
              onTapOutside: (_) => widget.onDismiss(),
              child: _buildCard(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(SmeltState state) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _popupWidth(),
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: ScrapTheme.cardSurface,
            borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
            border: Border.all(color: ScrapTheme.dividers, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000), // ~5% black
                offset: Offset(0, 4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tape strip header
              Transform.rotate(
                angle: -1.5 * math.pi / 180,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: ScrapTheme.tape,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: ScrapTheme.kraft.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  ),
                  child: const Center(
                    child: ScrapStampLabel(
                      text: '⟨ Smelt ⟩',
                      tiltDegrees: 0,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: _buildContent(state),
                ),
              ),
            ],
          ),
        ),
        // Torn bottom deckle — page colour notches so the slip looks torn
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 10,
          child: IgnorePointer(
            child: CustomPaint(
              painter: TornEdgePainter(
                seed: 42,
                amplitude: 3.5,
                fillColor: Color(0xFFF5F4F0), // ScrapTheme.background
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(SmeltState state) {
    if (state.isLoading) {
      return _buildLoadingState();
    }
    if (state.error != null) {
      return _buildErrorState(state.error!);
    }
    if (state.response == null) {
      return const SizedBox();
    }
    return _buildResponseContent(state.response!, state.showSteps);
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const _ThinkingDots(),
          const SizedBox(width: 12),
          Text(
            'Smelting...',
            style: ScrapTextStyles.body.copyWith(
              color: ScrapTheme.mutedText,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
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
            Icon(Icons.error_outline, size: 18, color: Colors.redAccent.shade400),
            const SizedBox(width: 8),
            Text(
              isMissingKey ? 'API key needed' : 'Error',
              style: ScrapTextStyles.body.copyWith(
                color: Colors.redAccent.shade400,
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
          TextButton(
            onPressed: () async {
              final saved = await showApiKeyDialog(context, allowSkip: false);
              if (saved == true && mounted) {
                ref.read(smeltProvider.notifier).clearState();
              }
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Add key',
              style: ScrapTextStyles.body.copyWith(
                color: ScrapTheme.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResponseContent(SmeltResponse response, bool showSteps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (response.isMath) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ScrapTheme.accentSurface,
              borderRadius: BorderRadius.circular(8),
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
          GestureDetector(
            onTap: () => ref.read(smeltProvider.notifier).toggleSteps(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ScrapTheme.dividers),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showSteps ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: ScrapTheme.mutedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showSteps ? 'Hide steps' : 'Show steps',
                    style: ScrapTextStyles.caption.copyWith(
                      color: ScrapTheme.mutedText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showSteps) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ScrapTheme.codeSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildMathSteps(response.steps),
            ),
          ],
        ],
        const SizedBox(height: 12),
        _buildChatHandoff(response),
        const SizedBox(height: 8),
        _buildModelFinePrint(response.modelUsed),
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
    widget.onDismiss();
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

  /// Build fine print showing which Gemini model was used
  Widget _buildModelFinePrint(String modelUsed) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        'Powered by ${_formatModelName(modelUsed)}',
        style: ScrapTextStyles.stamp.copyWith(
          color: ScrapTheme.mutedText,
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  /// Format model name for display (e.g., "gemini-2.0-flash-exp" -> "Gemini 2.0 Flash")
  String _formatModelName(String model) {
    if (model.contains('gemini')) {
      return model.split('-').map((part) {
        if (RegExp(r'^\d').hasMatch(part)) return part; // Keep version numbers as-is
        if (part.isEmpty) return '';
        return part[0].toUpperCase() + part.substring(1);
      }).where((part) => part.isNotEmpty).join(' ');
    }
    return model;
  }

  /// Build math answer — uses the same delimiter-aware renderer as steps,
  /// because answers often look like `\(x=1\) or \(x=2\)` (not a single Math.tex blob).
  Widget _buildMathAnswer(String answer) {
    return LatexMarkdownView(
      text: answer,
      baseStyle: ScrapTextStyles.body.copyWith(
        fontSize: 16,
        height: 1.4,
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

/// Animated thinking dots for loading state
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ember = Color(0xFF8A6A55);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final progress = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity =
                progress < 0.5 ? progress * 2 : 2 - progress * 2;
            // Stagger accent → ember for a furnace glow
            final color = Color.lerp(ScrapTheme.accent, ember, index / 2)!;
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}