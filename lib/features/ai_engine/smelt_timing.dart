import 'package:flutter/foundation.dart';

/// Sequential timing logs for one Smelt run.
///
/// Filter the console with `SMELT_TIMING`. Each line has wall-clock time,
/// elapsed since the run started, and delta since the previous step so
/// client-side delays (capture, compress, encode, parse) are easy to spot.
class SmeltTiming {
  SmeltTiming._();

  static int _runId = 0;
  static DateTime? _start;
  static DateTime? _last;

  static int begin({Map<String, Object?> extra = const {}}) {
    _runId += 1;
    _start = DateTime.now();
    _last = _start;
    step('begin', extra: extra);
    return _runId;
  }

  static void step(String name, {Map<String, Object?> extra = const {}}) {
    final now = DateTime.now();
    final start = _start ?? now;
    final last = _last ?? now;
    _last = now;

    final elapsedMs = now.difference(start).inMicroseconds / 1000.0;
    final deltaMs = now.difference(last).inMicroseconds / 1000.0;
    final extras = extra.entries
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    final extraPart = extras.isEmpty ? '' : ' $extras';

    debugPrint(
      'SMELT_TIMING run=$_runId [${now.toIso8601String()}] '
      '+${elapsedMs.toStringAsFixed(1)}ms Δ${deltaMs.toStringAsFixed(1)}ms '
      '| $name$extraPart',
    );
  }
}
