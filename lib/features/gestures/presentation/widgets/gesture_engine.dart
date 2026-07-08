import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/gesture_action.dart';
import '../providers/gesture_providers.dart';
import 'expanding_ring_feedback.dart';
import 'morse_gesture_zone.dart';

class GestureEngine extends ConsumerStatefulWidget {
  final Widget child;

  const GestureEngine({super.key, required this.child});

  @override
  ConsumerState<GestureEngine> createState() => _GestureEngineState();
}

class _GestureEngineState extends ConsumerState<GestureEngine> {
  // Config
  static const double _edgeZone = 48.0;
  static const double _velocityThreshold = 600.0;

  // Trackers
  final Map<int, PointerEvent> _activePointers = {};
  Timer? _holdTimer;
  int _holdStage = 0;
  Offset? _holdPosition;
  
  int _tapCount = 0;
  Timer? _doubleTapTimer;

  // Conflict resolution:
  // If multi-finger touch happens, cancel single-finger hold timer.
  // Swipe velocity is calculated upon PointerUp across all tracked points.

  void _onPointerDown(PointerDownEvent event) {
    // If it's bottom-left corner and morse is enabled, let morse zone handle it if we wanted strict exclusivity.
    // However, Listener captures all touches. We don't want to cancel canvas ink. 
    // In a full app, HitTestBehavior avoids stealing from Canvas, but we just want gesture recognition.
    
    _activePointers[event.pointer] = event;

    if (_activePointers.length == 1) {
       _holdStage = 0;
       _holdPosition = event.position;
       _holdTimer?.cancel();
       
       if (ref.read(tapHoldExpandEnabledProvider)) {
         _holdTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
           setState(() {
             if (_holdStage < 3) _holdStage++;
           });
           
           if (_holdStage == 3) {
             timer.cancel(); // Max stage 3 (900ms)
             // Document level analysis dispatch
           }
         });
       }
    } else {
       // Multi-touch invalidates tap-hold
       _holdTimer?.cancel();
       setState(() {
         _holdStage = 0;
         _holdPosition = null;
       });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
     final startEvent = _activePointers.remove(event.pointer);
     final pointerCountBeforeUp = _activePointers.length + 1;
     
     if (startEvent != null && startEvent is PointerDownEvent) {
        // Calculate velocity metrics
        final duration = event.timeStamp - startEvent.timeStamp;
        // avoid div by 0
        final seconds = duration.inMilliseconds / 1000.0;
        final secondsSafe = seconds > 0.01 ? seconds : 0.01;
        
        final distance = (event.position - startEvent.position);
        final velocityX = distance.dx / secondsSafe;
        final velocityY = distance.dy / secondsSafe;

        final size = MediaQuery.of(context).size;

        // --- Edge Swipes (1 pointer) ---
        if (pointerCountBeforeUp == 1 && ref.read(edgeSwipesEnabledProvider)) {
           if (startEvent.position.dx < _edgeZone && velocityX > _velocityThreshold) {
              ref.read(gestureActionProvider.notifier).dispatch(GestureAction.openDocumentNavigator);
            } else if (startEvent.position.dy > size.height - _edgeZone && velocityY < -_velocityThreshold) {
              ref.read(gestureActionProvider.notifier).dispatch(GestureAction.openSettingsPanel);
           }
        }
        
        // --- Multi-finger Swipes (4 pointers) ---
        if (pointerCountBeforeUp == 4 && ref.read(multiFingerEnabledProvider)) {
           if (velocityY < -_velocityThreshold) {
              ref.read(gestureActionProvider.notifier).dispatch(GestureAction.focusModeEnter);
           } else if (velocityY > _velocityThreshold) {
              ref.read(gestureActionProvider.notifier).dispatch(GestureAction.focusModeExit);
           }
        }

        // --- 2-finger double tap ---
        if (pointerCountBeforeUp == 2 && distance.distance < 20 && ref.read(multiFingerEnabledProvider)) {
            _tapCount++;
            if (_tapCount == 2) {
               ref.read(gestureActionProvider.notifier).dispatch(GestureAction.toggleAnnotationToolbar);
               _tapCount = 0;
            } else {
               _doubleTapTimer?.cancel();
               _doubleTapTimer = Timer(const Duration(milliseconds: 300), () {
                 _tapCount = 0;
               });
            }
        }
     }

     _holdTimer?.cancel();
     if (_activePointers.isEmpty) {
        setState(() {
           _holdStage = 0;
           _holdPosition = null;
        });
     }
  }

  void _onPointerCancel(PointerCancelEvent event) {
      _activePointers.remove(event.pointer);
      _holdTimer?.cancel();
      if (_activePointers.isEmpty) {
         setState(() {
           _holdStage = 0;
           _holdPosition = null;
        });
      }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          behavior: HitTestBehavior.translucent, // Passes touch through to Canvas / ScrollViews
          child: widget.child,
        ),

        // Visual Feedback Layer
        if (_holdStage > 0 && _holdPosition != null)
           ExpandingRingFeedback(position: _holdPosition!, stage: _holdStage),

        // Morse zone overlays on top of the tree, bottom-left
        const MorseGestureZone(),
      ],
    );
  }
}
