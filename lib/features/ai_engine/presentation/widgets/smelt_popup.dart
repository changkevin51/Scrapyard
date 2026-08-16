import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../../onboarding/presentation/providers/smelt_guide_provider.dart';
import '../../../onboarding/presentation/smelt_guide_keys.dart';
import '../../smelt_timing.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import '../providers/smelt_provider.dart';
import 'api_key_dialog.dart';
import 'latex_markdown_view.dart';

enum _PopupSide { below, above, right, left }

/// Popup widget that displays the smelt AI response
class SmeltPopup extends ConsumerStatefulWidget {
  final Rect selectionRect;
  final VoidCallback onDismiss;
  final VoidCallback onCollapse;
  final VoidCallback onTryAnotherModel;
  final ValueChanged<SmeltResponse>? onTapeOntoScrap;
  final Size screenSize;
  /// Snapshot of smelt UI state. When set, the popup ignores [smeltProvider].
  final SmeltState? frozenState;
  /// Screen-space rect of another popup to avoid overlapping.
  final Rect? avoidRect;
  /// Reports the popup's current screen bounds after layout / drag.
  final ValueChanged<Rect>? onBoundsChanged;

  const SmeltPopup({
    super.key,
    required this.selectionRect,
    required this.onDismiss,
    required this.onCollapse,
    required this.onTryAnotherModel,
    this.onTapeOntoScrap,
    required this.screenSize,
    this.frozenState,
    this.avoidRect,
    this.onBoundsChanged,
  });

  @override
  ConsumerState<SmeltPopup> createState() => SmeltPopupState();
}

class SmeltPopupState extends ConsumerState<SmeltPopup>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _rotateAnim;
  late Animation<double> _shakeAnim;
  bool _closing = false;
  bool _measured = false;
  Size? _cardSize;
  Offset? _dragPosition;
  _PopupSide _side = _PopupSide.below;
  double _maxHeight = 400;
  EdgeInsets _safePadding = EdgeInsets.zero;
  late bool _localShowSteps;
  late bool _localShowCodeOutput;

  static const double _margin = 16.0;
  static const double _gap = 12.0;
  static const double _minSideSpace = 160.0;
  static const double _hardMaxHeight = 400.0;

  /// Current on-screen bounds of the popup card, if measured.
  Rect? get currentBounds {
    if (_cardSize == null) return null;
    final pos = _calculatePopupPosition();
    return Rect.fromLTWH(
      pos.dx,
      pos.dy,
      _cardSize!.width,
      math.min(_cardSize!.height, _maxHeight),
    );
  }

  @override
  void initState() {
    super.initState();
    _localShowSteps = widget.frozenState?.showSteps ?? false;
    _localShowCodeOutput = widget.frozenState?.showCodeOutput ?? false;
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
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -4, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: -3), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3, end: 2), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 2, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));
    // Entrance waits for first size measurement so placement is correct.
  }

  /// Reverse entrance animation, then notify the host to remove the overlay.
  Future<void> dismiss() async {
    if (ref.read(smeltGuideProvider).locksSmeltPopup) {
      _shakeController.forward(from: 0);
      return;
    }
    await forceDismiss();
  }

  /// Close regardless of outside-tap rules (used by the explicit close button).
  Future<void> forceDismiss() async {
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

  SmeltState _effectiveState({bool watch = false}) {
    final frozen = widget.frozenState;
    if (frozen != null) return frozen;
    return watch ? ref.watch(smeltProvider) : ref.read(smeltProvider);
  }

  void _tapeOntoScrap() {
    final live = _effectiveState();
    final response = live.response;
    if (response == null || live.isLoading) {
      _shakeController.forward(from: 0);
      return;
    }
    widget.onTapeOntoScrap?.call(response);
    forceDismiss();
  }

  void _notifyBounds() {
    final bounds = currentBounds;
    if (bounds != null) {
      widget.onBoundsChanged?.call(bounds);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SmeltPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragPosition != null &&
        oldWidget.screenSize != widget.screenSize &&
        _cardSize != null) {
      _dragPosition = _clampToScreen(_dragPosition!, _cardSize!);
    }
    if (oldWidget.avoidRect != widget.avoidRect && _cardSize != null) {
      _nudgeAwayFromAvoidRect();
    }
  }

  void _nudgeAwayFromAvoidRect() {
    if (widget.avoidRect == null || _cardSize == null) return;
    final size = Size(
      _popupWidth(),
      math.min(_cardSize!.height, _maxHeight),
    );
    final pos = _calculatePopupPosition();
    final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    if (!rect.overlaps(widget.avoidRect!)) return;
    final adjusted = _resolveAvoidOverlap(pos, size);
    if (adjusted != pos) {
      setState(() => _dragPosition = adjusted);
    }
  }

  /// Preferred popup width; grows for math, capped so it fits the screen.
  double _popupWidth() {
    const preferred = 420.0;
    const maxWidth = 480.0;
    final available = widget.screenSize.width - (_margin * 2);
    return math.min(maxWidth, math.min(preferred, available));
  }

  void _onCardSize(Size size) {
    if (!mounted || _cardSize == size) return;
    final first = !_measured;
    setState(() {
      _cardSize = size;
      _measured = true;
      if (_dragPosition == null) {
        _recomputePlacement(naturalHeight: size.height);
      } else {
        _dragPosition = _clampToScreen(_dragPosition!, size);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nudgeAwayFromAvoidRect();
      _notifyBounds();
    });
    if (first && !_closing) {
      _animController.forward();
    }
  }

  void _recomputePlacement({double? naturalHeight}) {
    final rect = widget.selectionRect;
    final screen = widget.screenSize;
    final pad = _safePadding;
    final popupWidth = _popupWidth();
    final desiredH = naturalHeight ?? _cardSize?.height ?? 220.0;

    final below = screen.height - pad.bottom - _margin - (rect.bottom + _gap);
    final above = rect.top - _gap - pad.top - _margin;
    final right = screen.width - pad.right - _margin - (rect.right + _gap);
    final left = rect.left - _gap - pad.left - _margin;

    final cappedDesired = math.min(desiredH, _hardMaxHeight);

    _PopupSide side;
    if (below >= cappedDesired) {
      side = _PopupSide.below;
    } else if (above >= cappedDesired) {
      side = _PopupSide.above;
    } else if (below >= _minSideSpace || above >= _minSideSpace) {
      side = above > below ? _PopupSide.above : _PopupSide.below;
    } else if (right >= popupWidth && right >= left) {
      side = _PopupSide.right;
    } else if (left >= popupWidth) {
      side = _PopupSide.left;
    } else {
      side = above > below ? _PopupSide.above : _PopupSide.below;
    }

    final free = switch (side) {
      _PopupSide.below => below,
      _PopupSide.above => above,
      _PopupSide.right => screen.height - pad.top - pad.bottom - _margin * 2,
      _PopupSide.left => screen.height - pad.top - pad.bottom - _margin * 2,
    };

    _side = side;
    // Never exceed free space on the chosen side; floor at 80 for usability.
    _maxHeight = math.min(_hardMaxHeight, math.max(free, 80.0));
  }

  Offset _calculatePopupPosition() {
    if (_dragPosition != null) return _dragPosition!;

    final rect = widget.selectionRect;
    final screen = widget.screenSize;
    final pad = _safePadding;
    final popupWidth = _popupWidth();
    final height = math.min(_cardSize?.height ?? 220.0, _maxHeight);

    double left;
    double top;

    switch (_side) {
      case _PopupSide.below:
        top = rect.bottom + _gap;
        left = rect.center.dx - popupWidth / 2;
      case _PopupSide.above:
        top = rect.top - height - _gap;
        left = rect.center.dx - popupWidth / 2;
      case _PopupSide.right:
        left = rect.right + _gap;
        top = rect.center.dy - height / 2;
      case _PopupSide.left:
        left = rect.left - popupWidth - _gap;
        top = rect.center.dy - height / 2;
    }

    left = left
        .clamp(
          pad.left + _margin,
          math.max(
            pad.left + _margin,
            screen.width - pad.right - _margin - popupWidth,
          ),
        )
        .toDouble();
    top = top
        .clamp(
          pad.top + _margin,
          math.max(
            pad.top + _margin,
            screen.height - pad.bottom - _margin - height,
          ),
        )
        .toDouble();

    // If clamping dragged us over the selection, prefer the other vertical
    // side (or a horizontal side) instead of sitting on top of the ink.
    var popupRect = Rect.fromLTWH(left, top, popupWidth, height);
    if (popupRect.overlaps(rect)) {
      final belowTop = rect.bottom + _gap;
      final aboveTop = rect.top - height - _gap;
      final belowFits = belowTop + height <=
          screen.height - pad.bottom - _margin;
      final aboveFits = aboveTop >= pad.top + _margin;

      if (_side != _PopupSide.below && belowFits) {
        top = belowTop;
        left = (rect.center.dx - popupWidth / 2)
            .clamp(
              pad.left + _margin,
              math.max(
                pad.left + _margin,
                screen.width - pad.right - _margin - popupWidth,
              ),
            )
            .toDouble();
      } else if (_side != _PopupSide.above && aboveFits) {
        top = aboveTop;
        left = (rect.center.dx - popupWidth / 2)
            .clamp(
              pad.left + _margin,
              math.max(
                pad.left + _margin,
                screen.width - pad.right - _margin - popupWidth,
              ),
            )
            .toDouble();
      } else {
        // Last resort: park beside the selection.
        final roomRight = screen.width - pad.right - _margin - rect.right;
        final roomLeft = rect.left - pad.left - _margin;
        if (roomRight >= popupWidth || roomRight > roomLeft) {
          left = rect.right + _gap;
        } else {
          left = rect.left - popupWidth - _gap;
        }
        left = left
            .clamp(
              pad.left + _margin,
              math.max(
                pad.left + _margin,
                screen.width - pad.right - _margin - popupWidth,
              ),
            )
            .toDouble();
        top = (rect.center.dy - height / 2)
            .clamp(
              pad.top + _margin,
              math.max(
                pad.top + _margin,
                screen.height - pad.bottom - _margin - height,
              ),
            )
            .toDouble();
      }
    }

    return _resolveAvoidOverlap(Offset(left, top), Size(popupWidth, height));
  }

  /// Shift [pos] so a card of [size] does not overlap [widget.avoidRect].
  Offset _resolveAvoidOverlap(Offset pos, Size size) {
    final avoid = widget.avoidRect;
    if (avoid == null) return pos;

    var left = pos.dx;
    var top = pos.dy;
    var popupRect = Rect.fromLTWH(left, top, size.width, size.height);
    if (!popupRect.overlaps(avoid)) return pos;

    final pad = _safePadding;
    final screen = widget.screenSize;
    final minLeft = pad.left + _margin;
    final maxLeft = math.max(
      minLeft,
      screen.width - pad.right - _margin - size.width,
    );
    final minTop = pad.top + _margin;
    final maxTop = math.max(
      minTop,
      screen.height - pad.bottom - _margin - size.height,
    );

    // Prefer sliding into the largest free region around the avoid rect.
    final candidates = <Offset>[
      Offset(left, avoid.top - size.height - _gap), // above avoid
      Offset(left, avoid.bottom + _gap), // below avoid
      Offset(avoid.left - size.width - _gap, top), // left of avoid
      Offset(avoid.right + _gap, top), // right of avoid
    ];

    Offset? best;
    var bestScore = double.negativeInfinity;
    for (final c in candidates) {
      final clamped = Offset(
        c.dx.clamp(minLeft, maxLeft).toDouble(),
        c.dy.clamp(minTop, maxTop).toDouble(),
      );
      final r = Rect.fromLTWH(clamped.dx, clamped.dy, size.width, size.height);
      if (r.overlaps(avoid)) continue;
      // Prefer staying near the original placement.
      final score = -((clamped.dx - pos.dx).abs() + (clamped.dy - pos.dy).abs());
      if (score > bestScore) {
        bestScore = score;
        best = clamped;
      }
    }

    return best ?? pos;
  }

  Offset _clampToScreen(Offset pos, Size size) {
    final pad = _safePadding;
    final screen = widget.screenSize;
    final left = pos.dx.clamp(
      pad.left + _margin,
      math.max(pad.left + _margin, screen.width - pad.right - _margin - size.width),
    ).toDouble();
    final top = pos.dy.clamp(
      pad.top + _margin,
      math.max(pad.top + _margin, screen.height - pad.bottom - _margin - size.height),
    ).toDouble();
    return Offset(left, top);
  }

  Alignment get _anchorAlignment {
    return switch (_side) {
      _PopupSide.below => Alignment.topCenter,
      _PopupSide.above => Alignment.bottomCenter,
      _PopupSide.right => Alignment.centerLeft,
      _PopupSide.left => Alignment.centerRight,
    };
  }

  @override
  Widget build(BuildContext context) {
    _safePadding = MediaQuery.viewPaddingOf(context);
    final state = _effectiveState(watch: true);
    final position = _calculatePopupPosition();
    final anchor = _anchorAlignment;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FadeTransition(
        opacity: _measured ? _fadeAnim : const AlwaysStoppedAnimation(0),
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: anchor,
          child: AnimatedBuilder(
            animation: Listenable.merge([_rotateAnim, _shakeAnim]),
            builder: (context, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: Transform.rotate(
                angle: _rotateAnim.value,
                alignment: anchor,
                child: child,
              ),
            ),
            child: TapRegion(
              groupId: 'smelt-popups',
              onTapOutside: (_) {
                if (ref.read(smeltGuideProvider).locksSmeltPopup) return;
                dismiss();
              },
              child: _MeasureSize(
                onChange: _onCardSize,
                child: _buildCard(state),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final live = _effectiveState(watch: true);
    final canTape = widget.onTapeOntoScrap != null &&
        !live.isLoading &&
        live.response != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        _dragPosition ??= _calculatePopupPosition();
      },
      onPanUpdate: (details) {
        final size = _cardSize ?? Size(_popupWidth(), 220);
        setState(() {
          _dragPosition = _clampToScreen(
            (_dragPosition ?? Offset.zero) + details.delta,
            size,
          );
        });
        _notifyBounds();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            const Expanded(
              child: TapeStrip(
                label: '⟨ Smelt ⟩',
                tiltDegrees: -1.5,
                margin: EdgeInsets.fromLTRB(8, 6, 4, 0),
              ),
            ),
            if (widget.onTapeOntoScrap != null)
              PaperIconButton(
                icon: Icons.content_paste,
                tooltip: live.isLoading
                    ? 'Wait for result to tape'
                    : 'Tape onto scrap',
                color: canTape ? ScrapTheme.accent : ScrapTheme.secondaryText,
                size: 32,
                iconSize: 18,
                onPressed: canTape
                    ? _tapeOntoScrap
                    : () => _shakeController.forward(from: 0),
              ),
            if (!ref.watch(smeltGuideProvider).locksSmeltPopup)
              PaperIconButton(
                icon: Icons.close,
                tooltip: 'Close',
                size: 32,
                iconSize: 18,
                onPressed: forceDismiss,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(SmeltState state) {
    // Keep header fixed; let the body shrink-wrap up to [_maxHeight] so
    // placement uses the true content height (Flexible would always expand).
    const headerReserve = 52.0;
    final bodyMax = math.max(80.0, _maxHeight - headerReserve);

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: _popupWidth(),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _maxHeight),
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
                _buildHeader(),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: bodyMax),
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
    final showSteps = widget.frozenState != null
        ? _localShowSteps
        : state.showSteps;
    final showCodeOutput = widget.frozenState != null
        ? _localShowCodeOutput
        : state.showCodeOutput;
    return _buildResponseContent(
      state.response!,
      showSteps: showSteps,
      showCodeOutput: showCodeOutput,
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
                SmeltTiming.begin(extra: {'source': 'retry_after_api_key'});
                ref.read(smeltProvider.notifier).startLoading();
                await ref.read(smeltProvider.notifier).retry();
                SmeltTiming.step('retry_returned');
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
    final hasAnswer = response.hasDirectAnswer;
    final hasSteps = response.steps.trim().isNotEmpty;
    // Process-style answers (proofs, etc.) live entirely in steps — no answer box.
    final stepsExpanded = hasSteps && (showSteps || !hasAnswer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasAnswer) ...[
          if (response.isMath) ...[
            Container(
              key: widget.frozenState == null ? SmeltGuideKeys.smeltAnswer : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ScrapTheme.accentSurface,
                borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusDefault),
              ),
              child: _buildMathAnswer(response.answer),
            ),
          ] else ...[
            KeyedSubtree(
              key: widget.frozenState == null
                  ? SmeltGuideKeys.smeltAnswer
                  : const ValueKey('frozen-smelt-answer'),
              child: SelectableText(
                response.answer,
                style: ScrapTextStyles.body.copyWith(fontSize: 15, height: 1.5),
              ),
            ),
          ],
        ],
        if (hasSteps) ...[
          if (hasAnswer) ...[
            const SizedBox(height: 12),
            KeyedSubtree(
              key: widget.frozenState == null
                  ? SmeltGuideKeys.showSteps
                  : const ValueKey('frozen-show-steps'),
              child: _buildExpandToggle(
                expanded: stepsExpanded,
                expandedLabel: 'Hide steps',
                collapsedLabel: 'Show steps',
                onTap: () {
                  if (widget.frozenState == null) {
                    ref.read(smeltGuideProvider.notifier).onShowStepsTapped();
                  }
                  if (widget.frozenState != null) {
                    setState(() => _localShowSteps = !_localShowSteps);
                  } else {
                    ref.read(smeltProvider.notifier).toggleSteps();
                  }
                },
              ),
            ),
          ],
          if (stepsExpanded) ...[
            if (hasAnswer) const SizedBox(height: 12),
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
            onTap: () {
              if (widget.frozenState != null) {
                setState(() => _localShowCodeOutput = !_localShowCodeOutput);
              } else {
                ref.read(smeltProvider.notifier).toggleCodeOutput();
              }
            },
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
    final showModelSwap = widget.frozenState == null;
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
            if (showModelSwap) _buildTryAnotherModelButton(),
            if (showModelSwap) const Spacer(),
            if (!showModelSwap) const Spacer(),
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
    final smelt = _effectiveState();
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
    forceDismiss();
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
          Align(
            alignment: Alignment.centerLeft,
            child: ChatSuggestionChips(
              highlightKey:
                  widget.frozenState == null ? SmeltGuideKeys.askNext : null,
              suggestions: response.suggestions,
              onSelected: (q) => _openChat(autoSend: q),
            ),
          ),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          key: widget.frozenState == null ? SmeltGuideKeys.continueInChat : null,
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

/// Reports child size changes via [onChange] after layout.
class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const _MeasureSize({
    required this.onChange,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final size = this.size;
    if (_oldSize == size) return;
    _oldSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChange(size);
    });
  }
}
