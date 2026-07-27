import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/scrap_motion.dart';
import '../theme/scrapyard_theme.dart';
import 'paper_grain.dart';
import 'scrap_stamp_label.dart';
import 'torn_edge_clipper.dart';

/// Rotated kraft/tape strip that carries a stamp label.
class TapeStrip extends StatelessWidget {
  final String label;
  final double tiltDegrees;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const TapeStrip({
    super.key,
    required this.label,
    this.tiltDegrees = -1.5,
    this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 0),
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDegrees * math.pi / 180,
      child: Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: ScrapTheme.tape,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: ScrapTheme.kraft.withValues(alpha: 0.6),
            width: 0.5,
          ),
        ),
        child: Center(
          child: ScrapStampLabel(text: label, tiltDegrees: 0),
        ),
      ),
    );
  }
}

/// Shared paper dialog / popup / sheet shell.
class PaperSheet extends StatelessWidget {
  final Widget child;
  final int seed;
  final Set<TornEdge> edges;
  final double amplitude;
  final Color color;
  final bool grain;
  final double grainOpacity;
  final String? tapeLabel;
  final double? tapeTilt;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final BoxConstraints? constraints;

  /// When set, uses the cheap notch painter (single edge only).
  final Color? paintNotches;

  const PaperSheet({
    super.key,
    required this.child,
    this.seed = 42,
    this.edges = const {TornEdge.bottom},
    this.amplitude = 4.0,
    this.color = ScrapTheme.cardSurface,
    this.grain = false,
    this.grainOpacity = 0.02,
    this.tapeLabel,
    this.tapeTilt,
    this.padding,
    this.width,
    this.constraints,
    this.paintNotches,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = child;
    if (tapeLabel != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TapeStrip(
            label: tapeLabel!,
            tiltDegrees: tapeTilt ?? -1.5,
          ),
          if (padding != null)
            Padding(padding: padding!, child: child)
          else
            child,
        ],
      );
    } else if (padding != null) {
      body = Padding(padding: padding!, child: child);
    }

    Widget sheet = TornSheet(
      seed: seed,
      edges: edges,
      amplitude: amplitude,
      color: color,
      grain: grain,
      grainOpacity: grainOpacity,
      paintNotches: paintNotches,
      child: body,
    );

    if (width != null || constraints != null) {
      sheet = Container(
        width: width,
        constraints: constraints,
        child: sheet,
      );
    }
    return sheet;
  }
}

/// Small tilted note used for toasts and compact callouts.
class PaperChit extends StatelessWidget {
  final Widget child;
  final int seed;
  final double tiltDegrees;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool torn;

  const PaperChit({
    super.key,
    required this.child,
    this.seed = 19,
    this.tiltDegrees = -1.2,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.color = ScrapTheme.tape,
    this.torn = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget chit = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ScrapTheme.borderRadiusSmall),
        border: Border.all(
          color: ScrapTheme.kraft.withValues(alpha: 0.85),
          width: 0.75,
        ),
        boxShadow: ScrapTheme.deskShadow,
      ),
      child: child,
    );

    if (torn) {
      chit = Stack(
        clipBehavior: Clip.none,
        children: [
          chit,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 8,
            child: IgnorePointer(
              child: CustomPaint(
                painter: TornEdgePainter(
                  seed: seed,
                  amplitude: 2.2,
                  fillColor: ScrapTheme.background,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Transform.rotate(
      angle: tiltDegrees * math.pi / 180,
      child: chit,
    );
  }
}

/// Drop-in paper toast that replaces floating SnackBars.
Future<void> showPaperToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2200),
  Color? ink,
}) async {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _PaperToastEntry(
      message: message,
      duration: duration,
      ink: ink,
      onDone: () {
        entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _PaperToastEntry extends StatefulWidget {
  final String message;
  final Duration duration;
  final Color? ink;
  final VoidCallback onDone;

  const _PaperToastEntry({
    required this.message,
    required this.duration,
    required this.onDone,
    this.ink,
  });

  @override
  State<_PaperToastEntry> createState() => _PaperToastEntryState();
}

class _PaperToastEntryState extends State<_PaperToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: ScrapMotion.overlay);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: ScrapMotion.overlayCurve),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: ScrapMotion.overlayCurve));
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 28;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom, left: 24, right: 24),
          child: SlideTransition(
            position: _slide,
            child: ScaleTransition(
              scale: _scale,
              child: Material(
                color: Colors.transparent,
                child: PaperChit(
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: ScrapTextStyles.stamp.copyWith(
                      color: widget.ink ?? ScrapTheme.primaryText,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kraft paper-tab grabber for bottom sheets.
class PaperGrabber extends StatelessWidget {
  const PaperGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: ScrapTheme.kraft,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(
            color: ScrapTheme.dividers,
            width: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Soft paper grain backdrop for large sheets (optional convenience).
class PaperSheetBackdrop extends StatelessWidget {
  final Widget child;
  final double opacity;

  const PaperSheetBackdrop({
    super.key,
    required this.child,
    this.opacity = 0.02,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(child: PaperGrain(opacity: opacity)),
        ),
      ],
    );
  }
}
