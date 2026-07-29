import 'package:flutter/material.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../painters/logo_painter.dart';
import '../widgets/scrapyard_wordmark.dart';

/// Animated splash: vector paper-smiley draw-on, then Scrapyard wordmark.
///
/// Call [beginExit] when the host is ready to dismiss; [onExitComplete] fires
/// after the exit animation finishes.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onExitComplete,
    this.onIntroComplete,
    this.showLoadingHint = false,
  });

  final VoidCallback onExitComplete;
  final VoidCallback? onIntroComplete;
  final bool showLoadingHint;

  @override
  State<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  /// Fraction of the intro timeline reserved for the logo stroke choreography.
  static const double _logoShare = 0.62;

  late final AnimationController _intro;
  late final AnimationController _exit;

  late final Animation<double> _hintOpacity;
  late final Animation<double> _exitOpacity;
  late final Animation<double> _exitScale;

  bool _exiting = false;
  bool _introNotified = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3900),
    );

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _hintOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.88, 1.0, curve: Curves.easeIn),
      ),
    );

    _exitOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeOutCubic),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeOutCubic),
    );

    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _notifyIntroComplete();
      }
    });

    _exit.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onExitComplete();
      }
    });
  }

  void _notifyIntroComplete() {
    if (_introNotified) return;
    _introNotified = true;
    widget.onIntroComplete?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _startIntro();
  }

  void _startIntro() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1.0;
      _notifyIntroComplete();
      return;
    }
    _intro.forward();
  }

  /// Start the exit animation (or jump-complete if reduce-motion).
  void beginExit() {
    if (_exiting) return;
    _exiting = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onExitComplete();
      return;
    }

    if (_intro.status != AnimationStatus.completed) {
      _intro.forward().whenComplete(() {
        if (mounted) _exit.forward();
      });
    } else {
      _exit.forward();
    }
  }

  /// Whether the intro animation has finished.
  bool get introComplete => _intro.status == AnimationStatus.completed;

  @override
  void dispose() {
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoSize = (screenWidth * 0.42).clamp(160.0, 220.0);
    final wordSize = (screenWidth * 0.075).clamp(28.0, 40.0);

    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _exit]),
      builder: (context, _) {
        final t = _intro.value;
        final logoT = (t / _logoShare).clamp(0.0, 1.0);
        final logoState = logoAnimAt(logoT);
        final wordState = wordmarkAnimAt(t);

        final brandSettle = t < 0.41
            ? 0.0
            : Curves.easeOutCubic.transform(
                ((t - 0.41) / 0.45).clamp(0.0, 1.0),
              );
        final logoShift = -10.0 * brandSettle;

        return Opacity(
          opacity: _exitOpacity.value,
          child: Transform.scale(
            scale: _exitScale.value,
            child: ColoredBox(
              color: ScrapTheme.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.translate(
                      offset: Offset(0, logoShift),
                      child: SizedBox(
                        width: logoSize,
                        height: logoSize,
                        child: CustomPaint(
                          painter: AnimatedLogoPainter(
                            state: logoState,
                            color: ScrapTheme.primaryText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Transform.translate(
                      offset: Offset(0, 14 * (1 - brandSettle)),
                      child: ScrapyardWordmark(
                        state: wordState,
                        fontSize: wordSize,
                      ),
                    ),
                    if (widget.showLoadingHint) ...[
                      const SizedBox(height: 32),
                      Opacity(
                        opacity: _hintOpacity.value,
                        child: Text(
                          '⟨ loading scraps ⟩',
                          style: ScrapTextStyles.stamp.copyWith(
                            color: ScrapTheme.mutedText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
