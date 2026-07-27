import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/presentation/providers/home_providers.dart';
import '../providers/splash_providers.dart';
import '../screens/splash_screen.dart';

/// Wraps the router child so [HomeScreen] mounts and loads under an opaque
/// splash overlay. Dismisses when the intro finishes AND notes are ready
/// (or after a hard timeout).
class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  static const _hardTimeout = Duration(seconds: 4);
  static const _loadingHintAfter = Duration(milliseconds: 2500);

  final GlobalKey<SplashScreenState> _splashKey = GlobalKey();

  bool _gone = false;
  bool _exitStarted = false;
  bool _introDone = false;
  bool _timedOut = false;
  bool _showLoadingHint = false;

  Timer? _timeout;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();

    _timeout = Timer(_hardTimeout, () {
      _timedOut = true;
      _tryExit();
    });
    _hintTimer = Timer(_loadingHintAfter, () {
      if (!_gone && mounted) {
        setState(() => _showLoadingHint = true);
      }
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  bool get _nodesReady {
    final nodes = ref.read(currentHomeNodesProvider);
    return nodes.hasValue || nodes.hasError;
  }

  void _onIntroComplete() {
    _introDone = true;
    _tryExit();
  }

  void _tryExit() {
    if (_exitStarted || _gone) return;

    // Need intro done (or hard timeout forcing beginExit to finish intro).
    final canLeave = (_introDone && (_nodesReady || _timedOut)) || _timedOut;
    if (!canLeave) return;

    _exitStarted = true;
    _timeout?.cancel();
    _hintTimer?.cancel();

    final splash = _splashKey.currentState;
    if (splash != null) {
      splash.beginExit();
    } else {
      _onExitComplete();
    }
  }

  void _onExitComplete() {
    if (_gone || !mounted) return;
    setState(() => _gone = true);
    ref.read(appReadyProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the autoDispose home nodes provider alive so it loads under splash.
    ref.watch(currentHomeNodesProvider);

    ref.listen(currentHomeNodesProvider, (prev, next) {
      if (next.hasValue || next.hasError) {
        _tryExit();
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_gone)
          Positioned.fill(
            child: AbsorbPointer(
              child: SplashScreen(
                key: _splashKey,
                showLoadingHint: _showLoadingHint,
                onIntroComplete: _onIntroComplete,
                onExitComplete: _onExitComplete,
              ),
            ),
          ),
      ],
    );
  }
}
