import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrap_feedback.dart';
import '../../../../core/theme/scrap_motion.dart';
import '../../../../core/theme/scrapyard_theme.dart';
import '../../../../core/widgets/scrap_pressable.dart';
import '../../../../core/widgets/scrap_stamp_label.dart';
import '../../../ai_chat/presentation/providers/chat_providers.dart';
import '../../../ai_engine/presentation/providers/smelt_provider.dart';
import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../domain/smelt_guide_step.dart';
import '../providers/smelt_guide_provider.dart';
import '../smelt_guide_keys.dart';

/// App-wide coach overlay. Lives above the navigator so it can spotlight
/// OverlayEntry popups (Smelt answer / Show steps).
class SmeltGuideOverlay extends ConsumerStatefulWidget {
  const SmeltGuideOverlay({super.key});

  @override
  ConsumerState<SmeltGuideOverlay> createState() => _SmeltGuideOverlayState();
}

class _SmeltGuideOverlayState extends ConsumerState<SmeltGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _measureRetry;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _measureRetry?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Rect? _holesFor(SmeltGuideStep step, BuildContext overlayContext) {
    switch (step) {
      case SmeltGuideStep.openScrap:
        return _toOverlay(
          overlayContext,
          SmeltGuideKeys.rectOf(SmeltGuideKeys.newScrapButton),
        );
      case SmeltGuideStep.tapSmelt:
        return _toOverlay(
          overlayContext,
          SmeltGuideKeys.rectOf(SmeltGuideKeys.smeltTool),
        );
      case SmeltGuideStep.chooseSmelt:
        return _toOverlay(
          overlayContext,
          SmeltGuideKeys.unionOf([
            SmeltGuideKeys.smeltPill,
            SmeltGuideKeys.smeltCodePill,
          ]),
        );
      case SmeltGuideStep.showSteps:
        return _toOverlay(
          overlayContext,
          SmeltGuideKeys.rectOf(SmeltGuideKeys.showSteps),
        );
      case SmeltGuideStep.askNext:
        return _toOverlay(
          overlayContext,
          SmeltGuideKeys.rectOf(SmeltGuideKeys.askNext) ??
              SmeltGuideKeys.rectOf(SmeltGuideKeys.continueInChat),
        );
      case SmeltGuideStep.chatSelect:
        return _onscreenHole(
          overlayContext,
          SmeltGuideKeys.rectOf(SmeltGuideKeys.chatSelect),
        );
      default:
        return null;
    }
  }

  Rect? _answerRect(BuildContext overlayContext) => _toOverlay(
        overlayContext,
        SmeltGuideKeys.rectOf(SmeltGuideKeys.smeltAnswer),
      );

  /// Ignore a target that's still sliding in from off-screen (chat overlay).
  Rect? _onscreenHole(BuildContext overlayContext, Rect? global) {
    final local = _toOverlay(overlayContext, global);
    if (local == null) return null;
    final screen = MediaQuery.sizeOf(overlayContext);
    if (local.center.dx < 8 ||
        local.center.dx > screen.width - 8 ||
        local.center.dy < 8 ||
        local.center.dy > screen.height - 8) {
      return null;
    }
    return local;
  }

  /// GlobalKey rects are screen-space; paint this overlay in local space.
  Rect? _toOverlay(BuildContext overlayContext, Rect? global) {
    if (global == null) return null;
    final box = overlayContext.findRenderObject();
    if (box is! RenderBox || !box.attached) return global;
    return Rect.fromPoints(
      box.globalToLocal(global.topLeft),
      box.globalToLocal(global.bottomRight),
    );
  }

  void _scheduleRemeasure() {
    _measureRetry?.cancel();
    _measureRetry = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final guide = ref.watch(smeltGuideProvider);

    ref.listen(strokesProvider, (prev, next) {
      if (!ref.read(smeltGuideProvider).isActive) return;
      if (ref.read(smeltGuideProvider).step != SmeltGuideStep.writeProblem) {
        return;
      }
      if (next.isEmpty) return;
      ref.read(smeltGuideProvider.notifier).markInk();
    });

    ref.listen(canvasTextNodesProvider, (prev, next) {
      if (!ref.read(smeltGuideProvider).isActive) return;
      if (ref.read(smeltGuideProvider).step != SmeltGuideStep.writeProblem) {
        return;
      }
      if (next.isEmpty) return;
      ref.read(smeltGuideProvider.notifier).markInk();
    });

    ref.listen<CanvasTool>(activeCanvasToolProvider, (prev, next) {
      if (next == CanvasTool.smelt && prev != CanvasTool.smelt) {
        ref.read(smeltGuideProvider.notifier).onSmeltToolSelected();
      }
    });

    ref.listen<bool>(smeltGuideSelectionReadyProvider, (prev, next) {
      if (next) {
        ref.read(smeltGuideProvider.notifier).onSelectionReady();
      }
    });

    ref.listen<SmeltState>(smeltProvider, (prev, next) {
      ref.read(smeltGuideProvider.notifier).onSmeltEngine(next);
    });

    ref.listen<bool>(chatPanelOpenProvider, (prev, next) {
      if (next) {
        ref.read(smeltGuideProvider.notifier).onChatOpened();
      }
    });

    ref.listen(pendingChatSeedProvider, (prev, next) {
      if (next != null) {
        ref.read(smeltGuideProvider.notifier).onChatOpened();
      }
    });

    ref.listen(smeltGuideProvider, (prev, next) {
      if (next.step == SmeltGuideStep.openScrap) {
        ref.read(smeltGuideSelectionReadyProvider.notifier).state = false;
        if (ref.read(activeCanvasToolProvider) != CanvasTool.pen) {
          ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.pen;
        }
      }
      if (next.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncFromWorld();
        });
      }
    });

    if (!guide.isActive) return const SizedBox.shrink();

    final step = guide.step;
    final tooltipId =
        '${step.name}_${guide.isSmelting}_${guide.smeltFailed}_${guide.hasInk}_${guide.hasSelection}_${guide.stepsRevealed}';

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (overlayContext, _) {
          // Measure each pulse frame so sliding chat / popups stay aligned.
          final hole = (step == SmeltGuideStep.showSteps && guide.stepsRevealed)
              ? null
              : _holesFor(step, overlayContext)?.inflate(10);
          final answer = step.showArrowToAnswer && !guide.stepsRevealed
              ? _answerRect(overlayContext)
              : null;
          final useBarrier = step.usesBarrier &&
              hole != null &&
              !guide.isSmelting &&
              !(step == SmeltGuideStep.showSteps && guide.stepsRevealed);

          if (hole == null &&
              (step.usesBarrier ||
                  step == SmeltGuideStep.showSteps ||
                  step == SmeltGuideStep.askNext)) {
            _scheduleRemeasure();
          }

          final media = MediaQuery.sizeOf(overlayContext);
          final padding = MediaQuery.paddingOf(overlayContext);
          final tooltipSize = Size(
            math.min(340, media.width - 40),
            0,
          );
          final tooltipPos = _tooltipOffset(
            screen: media,
            padding: padding,
            hole: hole,
            tooltipWidth: tooltipSize.width,
            step: step,
          );

          return Stack(
            children: [
              if (useBarrier)
                Positioned.fill(
                  child: _GuideHoleBarrier(
                    hole: RRect.fromRectAndRadius(
                      hole,
                      const Radius.circular(8),
                    ),
                    child: CustomPaint(
                      painter: _GuideDimPainter(
                        hole: hole,
                        pulse: _pulse.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              if (step.showArrowToAnswer && answer != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GuideArrowPainter(
                        from: Offset(
                          tooltipPos.dx + tooltipSize.width * 0.35,
                          tooltipPos.dy - 6,
                        ),
                        to: Offset(answer.center.dx, answer.bottom),
                        pulse: _pulse.value,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: tooltipPos.dx,
                top: tooltipPos.dy,
                width: tooltipSize.width,
                child: _GuideTooltipCard(
                  key: ValueKey(tooltipId),
                  playEnter: true,
                  stamp: step.stampLabel,
                  body: guide.isSmelting
                      ? 'Smelting…'
                      : guide.smeltFailed
                          ? "Smelt didn't take — tap ⟨ Smelt ⟩ to try again."
                          : step == SmeltGuideStep.selectExpression &&
                                  guide.hasSelection
                              ? 'If it didn’t select properly, drag around the equation. Otherwise tap Next.'
                              : step == SmeltGuideStep.showSteps &&
                                      guide.stepsRevealed
                                  ? 'Read the work, then tap Next when you’re ready.'
                                  : step.body,
                  allowSkip: step.allowSkip && !guide.isSmelting,
                  actionLabel: guide.actionLabel,
                  onSkip: () {
                    ScrapFeedback.tap();
                    ref.read(smeltGuideProvider.notifier).skip();
                  },
                  onAction: () {
                    ScrapFeedback.tap();
                    ref.read(smeltGuideProvider.notifier).dismissSoftStep();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncFromWorld() {
    final notifier = ref.read(smeltGuideProvider.notifier);
    final guide = ref.read(smeltGuideProvider);
    if (!guide.isActive) return;

    if (guide.step == SmeltGuideStep.writeProblem) {
      final hasMarks = ref.read(strokesProvider).isNotEmpty ||
          ref.read(canvasTextNodesProvider).isNotEmpty;
      if (hasMarks) notifier.markInk();
    }
    if (guide.step == SmeltGuideStep.selectExpression &&
        ref.read(smeltGuideSelectionReadyProvider)) {
      notifier.onSelectionReady();
    }
  }

  Offset _tooltipOffset({
    required Size screen,
    required EdgeInsets padding,
    required Rect? hole,
    required double tooltipWidth,
    required SmeltGuideStep step,
  }) {
    const cardHeightGuess = 128.0;
    const gap = 16.0;

    if (step == SmeltGuideStep.writeProblem ||
        step == SmeltGuideStep.selectExpression ||
        step == SmeltGuideStep.chooseSmelt) {
      return Offset(
        (screen.width - tooltipWidth) / 2,
        padding.top + 20,
      );
    }

    if (step == SmeltGuideStep.chatSelect && hole != null) {
      var left = hole.center.dx - tooltipWidth / 2;
      left = left.clamp(16.0, screen.width - tooltipWidth - 16);
      final above = hole.top - gap - cardHeightGuess;
      final top = above > padding.top + 8
          ? above
          : padding.top + 20;
      return Offset(left, top);
    }

    if (step == SmeltGuideStep.enjoy) {
      return Offset(
        (screen.width - tooltipWidth) / 2,
        (screen.height - cardHeightGuess) / 2,
      );
    }

    if (hole == null) {
      return Offset(
        (screen.width - tooltipWidth) / 2,
        padding.top + 24,
      );
    }

    final below = hole.bottom + gap;
    if (below + cardHeightGuess < screen.height - padding.bottom - 12) {
      var left = hole.center.dx - tooltipWidth / 2;
      left = left.clamp(16.0, screen.width - tooltipWidth - 16);
      return Offset(left, below);
    }

    final above = hole.top - gap - cardHeightGuess;
    if (above > padding.top + 8) {
      var left = hole.center.dx - tooltipWidth / 2;
      left = left.clamp(16.0, screen.width - tooltipWidth - 16);
      return Offset(left, above);
    }

    // Side
    if (hole.right + gap + tooltipWidth < screen.width - 16) {
      return Offset(
        hole.right + gap,
        hole.top.clamp(padding.top + 8, screen.height - cardHeightGuess - 16),
      );
    }
    if (hole.left - gap - tooltipWidth > 16) {
      return Offset(
        hole.left - gap - tooltipWidth,
        hole.top.clamp(padding.top + 8, screen.height - cardHeightGuess - 16),
      );
    }

    return Offset(
      (screen.width - tooltipWidth) / 2,
      padding.top + 20,
    );
  }
}

class _GuideTooltipCard extends StatefulWidget {
  final bool playEnter;
  final String stamp;
  final String body;
  final bool allowSkip;
  final String? actionLabel;
  final VoidCallback onSkip;
  final VoidCallback onAction;

  const _GuideTooltipCard({
    super.key,
    required this.playEnter,
    required this.stamp,
    required this.body,
    required this.allowSkip,
    required this.actionLabel,
    required this.onSkip,
    required this.onAction,
  });

  @override
  State<_GuideTooltipCard> createState() => _GuideTooltipCardState();
}

class _GuideTooltipCardState extends State<_GuideTooltipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: ScrapMotion.cardEnter,
    );
    _fade = CurvedAnimation(parent: _enter, curve: ScrapMotion.overlayCurve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _enter, curve: ScrapMotion.cardEnterCurve),
    );
    if (widget.playEnter) {
      _enter.forward();
    } else {
      _enter.value = 1;
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Transform.rotate(
          angle: -0.6 * math.pi / 180,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: BoxDecoration(
                color: ScrapTheme.cardSurface,
                borderRadius:
                    BorderRadius.circular(ScrapTheme.borderRadiusDefault),
                border: Border.all(
                  color: ScrapTheme.kraft.withValues(alpha: 0.85),
                  width: 0.85,
                ),
                boxShadow: ScrapTheme.deskShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScrapStampLabel(text: widget.stamp),
                  const SizedBox(height: 10),
                  Text(
                    widget.body,
                    style: ScrapTextStyles.body.copyWith(
                      fontSize: 15,
                      height: 1.4,
                      color: ScrapTheme.bodyText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (widget.allowSkip)
                        ScrapPressable(
                          onTap: widget.onSkip,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 2,
                            ),
                            child: Text(
                              'Skip guide',
                              style: ScrapTextStyles.caption.copyWith(
                                color: ScrapTheme.mutedText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (widget.actionLabel != null)
                        ScrapPressable(
                          onTap: widget.onAction,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 4,
                            ),
                            child: Text(
                              widget.actionLabel!,
                              style: ScrapTextStyles.caption.copyWith(
                                color: ScrapTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
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
}

class _GuideHoleBarrier extends SingleChildRenderObjectWidget {
  final RRect hole;

  const _GuideHoleBarrier({required this.hole, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGuideHoleBarrier(hole);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderGuideHoleBarrier renderObject,
  ) {
    renderObject.hole = hole;
  }
}

class _RenderGuideHoleBarrier extends RenderProxyBox {
  _RenderGuideHoleBarrier(this._hole);

  RRect _hole;
  set hole(RRect value) {
    if (_hole == value) return;
    _hole = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_hole.outerRect.inflate(4).contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _GuideDimPainter extends CustomPainter {
  final Rect hole;
  final double pulse;
  final double dimOpacity;

  _GuideDimPainter({
    required this.hole,
    required this.pulse,
    this.dimOpacity = 0.28,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(8));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      dim,
      Paint()..color = ScrapTheme.primaryText.withValues(alpha: dimOpacity),
    );

    final expand = 3.0 + 4.0 * (0.5 + 0.5 * math.sin(pulse * math.pi * 2));
    final ring = rrect.inflate(expand);
    _drawDashedRRect(
      canvas,
      ring,
      Paint()
        ..color = ScrapTheme.accent.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    const dashLen = 7.0;
    const gapLen = 5.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final next = math.min(d + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuideDimPainter oldDelegate) {
    return oldDelegate.hole != hole ||
        oldDelegate.pulse != pulse ||
        oldDelegate.dimOpacity != dimOpacity;
  }
}

class _GuideArrowPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final double pulse;

  _GuideArrowPainter({
    required this.from,
    required this.to,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bob = math.sin(pulse * math.pi * 2) * 4;
    var end = to.translate(0, bob);
    var start = from;
    final delta = end - start;
    final dist = delta.distance;
    // Keep a short pointer into the answer instead of stretching across the popup.
    const maxLen = 56.0;
    if (dist > maxLen) {
      start = end - (delta / dist) * maxLen;
    }
    final mid = Offset(
      (start.dx + end.dx) / 2 + 8,
      (start.dy + end.dy) / 2,
    );
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);

    final paint = Paint()
      ..color = ScrapTheme.accent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    final tangent = (end - mid);
    final angle = math.atan2(tangent.dy, tangent.dx);
    const head = 9.0;
    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - head * math.cos(angle - 0.45),
        end.dy - head * math.sin(angle - 0.45),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - head * math.cos(angle + 0.45),
        end.dy - head * math.sin(angle + 0.45),
      );
    canvas.drawPath(headPath, paint);
  }

  @override
  bool shouldRepaint(covariant _GuideArrowPainter oldDelegate) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.pulse != pulse;
  }
}
