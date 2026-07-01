import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/koto_theme.dart';
import '../../domain/models/gesture_action.dart';
import '../providers/gesture_providers.dart';

class MorseGestureZone extends ConsumerStatefulWidget {
  const MorseGestureZone({super.key});

  @override
  ConsumerState<MorseGestureZone> createState() => _MorseGestureZoneState();
}

class _MorseGestureZoneState extends ConsumerState<MorseGestureZone> {
  final List<MorseSymbol> _currentPattern = [];
  DateTime? _pointerDownTime;
  Timer? _timeoutTimer;

  void _onPointerDown(PointerDownEvent event) {
    _pointerDownTime = DateTime.now();
    _timeoutTimer?.cancel();
    setState(() {}); // trigger active state render
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointerDownTime != null) {
      final elapsed = DateTime.now().difference(_pointerDownTime!).inMilliseconds;
      if (elapsed < 300) {
        _currentPattern.add(MorseSymbol.dot);
      } else {
        _currentPattern.add(MorseSymbol.dash);
      }
      
      _pointerDownTime = null;

      // Reset timer
      _timeoutTimer = Timer(const Duration(milliseconds: 800), _evaluatePattern);
      setState(() {});
    }
  }
  
  void _evaluatePattern() {
    if (_currentPattern.isNotEmpty) {
      final requestedPattern = MorsePattern(List.from(_currentPattern));
      final mappings = ref.read(morseMappingsProvider);
      
      GestureAction? action;
      for (final entry in mappings.entries) {
        if (entry.key == requestedPattern) {
          action = entry.value;
          break;
        }
      }

      if (action != null) {
        ref.read(gestureActionProvider.notifier).dispatch(action);
      }
      
      setState(() {
         _currentPattern.clear();
      });
    }
  }
  
  void _onPointerCancel(PointerCancelEvent event) {
     _pointerDownTime = null;
     setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(morseEnabledProvider);
    if (!enabled) return const SizedBox.shrink();

    // The indicator becomes 50% opacity when currently held down.
    final isActive = _pointerDownTime != null;

    return Positioned(
      bottom: 24,
      left: 24,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Container(
          width: 52,
          height: 52,
          color: Colors.transparent, // Touch zone
          alignment: Alignment.center,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isActive ? KotoTheme.accent.withValues(alpha: 0.5) : KotoTheme.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
