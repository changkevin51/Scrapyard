import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/math_reader_calculator_service.dart';
import '../../data/math_reader_python.dart';
import '../../domain/models/stroke.dart';
import '../../domain/services/equals_detector.dart';
import '../../domain/services/ink_geometry.dart';
import '../../domain/services/simple_arithmetic.dart';
import 'canvas_providers.dart';

const _prefsKeyOnDeviceCalc = 'canvas_on_device_calc';

/// App-wide toggle. Default off; no-ops on web (MathReader is not bundled there).
class OnDeviceCalcEnabledNotifier extends StateNotifier<bool> {
  OnDeviceCalcEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getBool(_prefsKeyOnDeviceCalc) ?? false;
    if (state) unawaited(ensureMathReaderSidecar());
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyOnDeviceCalc, value);
    if (value) {
      unawaited(ensureMathReaderSidecar());
    }
  }
}

final onDeviceCalcEnabledProvider =
    StateNotifierProvider<OnDeviceCalcEnabledNotifier, bool>((ref) {
  return OnDeviceCalcEnabledNotifier();
});

class InkCalculatorResult {
  final String noteId;
  final String pairKey;
  final Set<String> equalsStrokeIds;
  final Set<String> expressionStrokeIds;
  final Rect equalsBounds;
  final Rect expressionBounds;
  final Rect answerBounds;
  final String expression;
  final String latex;
  final String answerLatex;
  final String displayAnswer;
  /// Decimal twin of a fraction overlay answer; null when the overlay is already decimal/integer.
  final String? decimalAnswer;
  final Color color;
  final double fontSize;
  final double baselineY;

  const InkCalculatorResult({
    required this.noteId,
    required this.pairKey,
    required this.equalsStrokeIds,
    required this.expressionStrokeIds,
    required this.equalsBounds,
    required this.expressionBounds,
    required this.answerBounds,
    required this.expression,
    required this.latex,
    required this.answerLatex,
    required this.displayAnswer,
    this.decimalAnswer,
    required this.color,
    required this.fontSize,
    required this.baselineY,
  });

  Rect get hitBounds =>
      expressionBounds.expandToInclude(equalsBounds).expandToInclude(answerBounds);

  bool containsWorld(Offset world, {double pad = 0}) =>
      hitBounds.inflate(pad).contains(world);

  bool answerContains(Offset world, {double pad = 0}) =>
      answerBounds.inflate(pad).contains(world);
}

/// Debug-only: model's guessed expression when equals fired but solve failed.
class InkCalcDebugGuess {
  final int id;
  final String noteId;
  final String pairKey;
  final Rect bounds;
  final String latex;
  final String reason;
  final int strokeCount;

  const InkCalcDebugGuess({
    required this.id,
    required this.noteId,
    required this.pairKey,
    required this.bounds,
    required this.latex,
    required this.reason,
    this.strokeCount = 0,
  });
}

const _unset = Object();

class InkCalculatorState {
  final List<InkCalculatorResult> results;
  final Set<String> suppressedKeys;
  final InkCalcDebugGuess? debugGuess;

  const InkCalculatorState({
    this.results = const [],
    this.suppressedKeys = const {},
    this.debugGuess,
  });

  /// Most recent result for [noteId], if any.
  InkCalculatorResult? resultFor(String noteId) {
    for (var i = results.length - 1; i >= 0; i--) {
      if (results[i].noteId == noteId) return results[i];
    }
    return null;
  }

  List<InkCalculatorResult> resultsFor(String noteId) => [
        for (final r in results)
          if (r.noteId == noteId) r,
      ];

  InkCalculatorState copyWith({
    List<InkCalculatorResult>? results,
    Set<String>? suppressedKeys,
    Object? debugGuess = _unset,
  }) =>
      InkCalculatorState(
        results: results ?? this.results,
        suppressedKeys: suppressedKeys ?? this.suppressedKeys,
        debugGuess: identical(debugGuess, _unset)
            ? this.debugGuess
            : debugGuess as InkCalcDebugGuess?,
      );
}

final mathReaderCalculatorServiceProvider =
    Provider<MathReaderCalculatorService>((ref) {
  final service = MathReaderCalculatorService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final inkCalculatorProvider =
    StateNotifierProvider<InkCalculatorNotifier, InkCalculatorState>((ref) {
  return InkCalculatorNotifier(ref);
});

class InkCalculatorNotifier extends StateNotifier<InkCalculatorState> {
  InkCalculatorNotifier(this._ref) : super(const InkCalculatorState()) {
    _service = _ref.read(mathReaderCalculatorServiceProvider);
    _lastNoteId = _ref.read(activeNoteIdProvider);
    _ref.listen<List<Stroke>>(strokesProvider, _onStrokesChanged);
    _ref.listen<String>(activeNoteIdProvider, (prev, next) {
      _lastNoteId = next;
      if (prev == next) return;
      state = state.copyWith(
        results: [
          for (final r in state.results)
            if (r.noteId != prev) r,
        ],
        debugGuess: null,
      );
    });
    _ref.listen<bool>(onDeviceCalcEnabledProvider, (prev, next) {
      if (!next) {
        state = state.copyWith(results: const [], debugGuess: null);
        return;
      }
      _service.ensureModel();
    });
    if (_ref.read(onDeviceCalcEnabledProvider)) {
      _service.ensureModel();
    }
  }

  final Ref _ref;
  late final MathReaderCalculatorService _service;
  final Map<String, int> _solveGen = {};
  int _debugGuessId = 0;
  String? _lastNoteId;

  String get _noteId => _ref.read(activeNoteIdProvider);

  String _suppressKey(String pairKey) => '$_noteId::$pairKey';

  void removeAnswer({InkCalculatorResult? result, bool suppress = true}) {
    final target = result ?? state.resultFor(_noteId);
    if (target == null) return;
    final suppressed = suppress
        ? {...state.suppressedKeys, _suppressKey(target.pairKey)}
        : state.suppressedKeys;
    state = state.copyWith(
      results: [
        for (final r in state.results)
          if (r.pairKey != target.pairKey || r.noteId != target.noteId) r,
      ],
      suppressedKeys: suppressed,
    );
  }

  void clearDebugGuess() {
    if (state.debugGuess == null) return;
    state = state.copyWith(debugGuess: null);
  }

  /// Pen/brush drew over the answer — drop it and do not refill this equals.
  void dismissFromDrawOver() => removeAnswer(suppress: true);

  /// Eraser passed through the answer (no ink there to hide).
  void onEraseAt(Offset world, double radius) {
    final hits = [
      for (final r in state.resultsFor(_noteId))
        if (r.answerContains(world, pad: radius)) r,
    ];
    for (final r in hits) {
      removeAnswer(result: r, suppress: true);
    }
  }

  void _onStrokesChanged(List<Stroke>? previous, List<Stroke> next) {
    if (!_ref.read(onDeviceCalcEnabledProvider)) return;
    if (!MathReaderCalculatorService.isPlatformSupported) return;

    final noteId = _ref.read(activeNoteIdProvider);
    if (_lastNoteId != noteId) {
      _lastNoteId = noteId;
      return;
    }
    if (previous == null) return;

    final live = {
      for (final s in next)
        if (isCalcInk(s)) s.id,
    };
    final kept = [
      for (final r in state.results)
        if (r.noteId != noteId ||
            (r.equalsStrokeIds.every(live.contains) &&
                r.expressionStrokeIds.every(live.contains)))
          r,
    ];
    if (kept.length != state.results.length) {
      state = state.copyWith(results: kept);
    }

    final prevIds = {for (final s in previous) s.id};
    final added = [
      for (final s in next)
        if (!prevIds.contains(s.id) && isCalcInk(s)) s,
    ];

    if (added.isEmpty) return;
    // Ignore bulk loads / paste — this feature only follows live writing.
    if (added.length > 2) return;

    final newest = added.last;
    final newestBounds = strokeWorldBounds(newest);

    var drewOverAnswer = false;
    for (final showing in [...state.resultsFor(noteId)]) {
      if (newestBounds.overlaps(showing.answerBounds.inflate(6))) {
        removeAnswer(result: showing, suppress: true);
        drewOverAnswer = true;
        continue;
      }
      final exprHit = showing.expressionBounds.inflate(10);
      if (newestBounds.overlaps(exprHit) &&
          !showing.equalsStrokeIds.contains(newest.id)) {
        _trySolve(next, involvingId: showing.equalsStrokeIds.first);
        return;
      }
    }
    if (drewOverAnswer) return;

    _trySolve(next, involvingId: newest.id);
  }

  void _publishDebugGuess({
    required String noteId,
    required String pairKey,
    required Rect bounds,
    required String latex,
    required String reason,
    int strokeCount = 0,
  }) {
    if (!kDebugMode || !mounted) return;
    debugPrint(
      'MathReader debug popup latex="$latex" reason=$reason strokes=$strokeCount bounds=$bounds',
    );
    state = state.copyWith(
      debugGuess: InkCalcDebugGuess(
        id: ++_debugGuessId,
        noteId: noteId,
        pairKey: pairKey,
        bounds: bounds,
        latex: latex,
        reason: reason,
        strokeCount: strokeCount,
      ),
    );
  }

  Future<void> _trySolve(List<Stroke> strokes, {String? involvingId}) async {
    if (!_ref.read(onDeviceCalcEnabledProvider)) return;

    final noteId = _ref.read(activeNoteIdProvider);
    final ignored = <String>{};
    for (final r in state.resultsFor(noteId)) {
      if (involvingId != null && r.equalsStrokeIds.contains(involvingId)) {
        continue;
      }
      ignored.addAll(r.expressionStrokeIds);
      ignored.addAll(r.equalsStrokeIds);
    }
    var detection = detectEquals(
      strokes,
      involvingStrokeId: involvingId,
      ignoredIds: ignored,
    );
    if (detection == null && kDebugMode) {
      detection = detectEquals(
        strokes,
        involvingStrokeId: involvingId,
        ignoredIds: ignored,
        lenient: true,
      );
      if (detection != null) {
        debugPrint(
          'MathReader: lenient equals ${detection.pairKey} exprStrokes=${detection.expressionStrokeIds.length}',
        );
      }
    }
    if (detection == null) {
      Stroke? involved;
      for (final s in strokes) {
        if (s.id == involvingId) {
          involved = s;
          break;
        }
      }
      if (involved != null && isHorizontalBar(involved)) {
        debugPrint('MathReader: no equals pair for bar $involvingId');
      }
      return;
    }
    debugPrint(
      'MathReader: equals ${detection.pairKey} exprStrokes=${detection.expressionStrokeIds.length}',
    );
    if (state.suppressedKeys.contains(_suppressKey(detection.pairKey))) return;

    final existing = [
      for (final r in state.results)
        if (r.noteId == noteId && r.pairKey == detection.pairKey) r,
    ];
    if (existing.isNotEmpty &&
        setEquals(
          existing.first.expressionStrokeIds,
          detection.expressionStrokeIds,
        )) {
      return;
    }

    final guessBounds =
        detection.expressionBounds.expandToInclude(detection.equalsBounds);

    if (!_service.isReady) {
      debugPrint('MathReader: waiting for sidecar…');
      await _service.ensureModel();
      if (!_service.isReady) {
        debugPrint('MathReader: sidecar not ready, skip solve');
        if (!mounted || _ref.read(activeNoteIdProvider) != noteId) return;
        _publishDebugGuess(
          noteId: noteId,
          pairKey: detection.pairKey,
          bounds: guessBounds,
          latex: '',
          reason: 'sidecar not ready',
          strokeCount: detection.expressionStrokes.length,
        );
        return;
      }
    }

    final gen = (_solveGen[detection.pairKey] ?? 0) + 1;
    _solveGen[detection.pairKey] = gen;

    final recognized =
        await _service.recognizeLatex(detection.expressionStrokes);
    if (!mounted) return;
    if (_ref.read(activeNoteIdProvider) != noteId) return;

    final latex = recognized.latex;
    final plain = latex == null ? null : latexToArithmetic(latex);
    final solved = plain == null ? null : tryEvaluateArithmetic(plain);
    final stale = _solveGen[detection.pairKey] != gen;
    // Keep any existing answer if this pass could not solve.
    if (solved == null) {
      debugPrint(
        'MathReader: could not evaluate latex=$latex error=${recognized.error} stale=$stale sidecar=${recognized.sidecarRev}',
      );
      var reason = recognized.error ??
          (latex == null || latex.isEmpty
              ? 'empty recognition'
              : 'could not evaluate');
      if (recognized.isStaleSidecar) {
        reason =
            '$reason — stale Python sidecar ${recognized.sidecarRev ?? 'old'}. '
            'Fully quit the app (press q), then flutter run.';
      }
      _publishDebugGuess(
        noteId: noteId,
        pairKey: detection.pairKey,
        bounds: guessBounds,
        latex: latex ?? '',
        reason: reason,
        strokeCount: detection.expressionStrokes.length,
      );
      return;
    }
    if (stale) return;

    final ops = detectArithmeticOperators(detection.expressionStrokes);
    final opIds = {for (final o in ops) ...o.strokeIds};
    final digitStrokes = [
      for (final s in detection.expressionStrokes)
        if (!opIds.contains(s.id) && !isHorizontalBar(s)) s,
    ];
    final digitBounds = digitStrokes.isEmpty
        ? detection.equalsBounds
        : unionBounds(digitStrokes.map(strokeWorldBounds));
    final eqH = detection.equalsBounds.height.clamp(12.0, 64.0);
    final stacked =
        detection.expressionBounds.height > detection.equalsBounds.height * 2.2;
    final glyphHs = [
      for (final s in digitStrokes) strokeWorldBounds(s).height,
    ]..sort();
    final typicalGlyph = glyphHs.isEmpty
        ? eqH
        : glyphHs[glyphHs.length ~/ 2];
    // Stacked fractions/sqrts are tall; size the answer to a single glyph,
    // not the whole stack. Fraction answers (`5/6`) get a slightly larger hand.
    final sizeSrc = stacked ? math.max(eqH, typicalGlyph) : math.max(typicalGlyph, eqH);
    final fractionAnswer = solved.displaysAsFraction;
    final fontSize = (sizeSrc * (fractionAnswer ? 1.62 : 1.48))
        .clamp(24.0, stacked ? (fractionAnswer ? 70.0 : 60.0) : 104.0);
    final answerLeft =
        detection.equalsBounds.right + math.max(8.0, sizeSrc * 0.16);
    final answerWidth = math.max(
      fontSize * 0.9,
      solved.display.length * fontSize * 0.68,
    );
    final baselineY = stacked
        ? detection.equalsBounds.center.dy + fontSize * 0.32
        : digitBounds.bottom - sizeSrc * 0.22;
    final answerTop = baselineY - fontSize;
    final answerHeight = fontSize * 1.4;

    final next = InkCalculatorResult(
      noteId: noteId,
      pairKey: detection.pairKey,
      equalsStrokeIds: detection.equalsStrokeIds,
      expressionStrokeIds: detection.expressionStrokeIds,
      equalsBounds: detection.equalsBounds,
      expressionBounds: detection.expressionBounds,
      answerBounds: Rect.fromLTWH(
        answerLeft,
        answerTop,
        answerWidth,
        answerHeight,
      ),
      expression: solved.expression,
      latex: solved.latex,
      answerLatex: solved.answerLatex,
      displayAnswer: solved.display,
      decimalAnswer: solved.displaysAsFraction ? solved.decimalDisplay : null,
      color: detection.color,
      fontSize: fontSize,
      baselineY: baselineY,
    );

    state = state.copyWith(
      results: [
        for (final r in state.results)
          if (!(r.noteId == noteId && r.pairKey == detection.pairKey)) r,
        next,
      ],
      debugGuess: null,
    );
  }
}
