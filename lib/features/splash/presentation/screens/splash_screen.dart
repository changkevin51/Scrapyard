import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../../../core/theme/scrapyard_theme.dart';

/// Animated splash: paper-drop logo, then left-to-right wordmark wipe.
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
  static const _logoAsset = 'assets/images/SplashLogo.png';
  static const _textAsset = 'assets/images/SplashText.png';

  late final AnimationController _intro;
  late final AnimationController _exit;

  // Paper drop (0.05–0.42)
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoTranslateY;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoRotation;
  late final Animation<double> _shadowBlur;
  late final Animation<double> _shadowOffsetY;

  // Settle wobble (0.42–0.55)
  late final Animation<double> _settleRotation;

  // Wordmark wipe (0.38–0.75)
  late final Animation<double> _textReveal;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textTranslateY;

  // Loading hint fade (0.85–1.0 of intro, only when waiting)
  late final Animation<double> _hintOpacity;

  // Exit
  late final Animation<double> _exitOpacity;
  late final Animation<double> _exitScale;

  bool _imagesReady = false;
  bool _exiting = false;
  bool _introNotified = false;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    final dropCurve = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.05, 0.42, curve: Curves.easeOutCubic),
    );

    _logoOpacity = Tween<double>(begin: 0, end: 1).animate(dropCurve);
    _logoTranslateY = Tween<double>(begin: -56, end: 0).animate(dropCurve);
    _logoScale = Tween<double>(begin: 1.10, end: 1.0).animate(dropCurve);
    _logoRotation = Tween<double>(begin: -0.07, end: 0).animate(dropCurve);
    _shadowBlur = Tween<double>(begin: 34, end: 10).animate(dropCurve);
    _shadowOffsetY = Tween<double>(begin: 18, end: 5).animate(dropCurve);

    _settleRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.015)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.015, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.42, 0.55),
    ));

    final wipeCurve = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.38, 0.75, curve: Curves.easeOutCubic),
    );
    _textReveal = Tween<double>(begin: 0, end: 1).animate(wipeCurve);
    _textOpacity = Tween<double>(begin: 0, end: 1).animate(wipeCurve);
    _textTranslateY = Tween<double>(begin: 12, end: 0).animate(wipeCurve);

    _hintOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.85, 1.0, curve: Curves.easeIn),
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
    if (_imagesReady) return;
    _precacheAndStart();
  }

  Future<void> _precacheAndStart() async {
    await Future.wait([
      precacheImage(const AssetImage(_logoAsset), context),
      precacheImage(const AssetImage(_textAsset), context),
    ]);
    if (!mounted) return;
    _imagesReady = true;

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

    // Ensure intro is at least finished before exiting.
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
    final textWidth = (screenWidth * 0.55).clamp(180.0, 320.0);

    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _exit]),
      builder: (context, _) {
        final rotation = _logoRotation.value + _settleRotation.value;

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
                    // Paper drop logo — shadow follows PNG alpha (outline),
                    // not the widget's rectangular bounds.
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _logoTranslateY.value),
                        child: Transform.rotate(
                          angle: rotation,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  // Soft silhouette matching the ink strokes
                                  Transform.translate(
                                    offset: Offset(0, _shadowOffsetY.value),
                                    child: ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: _shadowBlur.value * 0.25,
                                        sigmaY: _shadowBlur.value * 0.25,
                                        tileMode: TileMode.decal,
                                      ),
                                      child: ColorFiltered(
                                        colorFilter: const ColorFilter.mode(
                                          Color(0x70000000),
                                          BlendMode.srcIn,
                                        ),
                                        child: Image.asset(
                                          _logoAsset,
                                          width: 200,
                                          height: 200,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Image.asset(
                                    _logoAsset,
                                    width: 200,
                                    height: 200,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Wordmark wipe
                    Opacity(
                      opacity: _textOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _textTranslateY.value),
                        child: SizedBox(
                          width: textWidth,
                          // 1254 x 188 aspect
                          height: textWidth * (188 / 1254),
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: _textReveal.value.clamp(0.0, 1.0),
                              child: Image.asset(
                                _textAsset,
                                width: textWidth,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Loading hint while waiting past intro hold
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
