// TEMPORARY debug-mode instrumentation helper (session 7a9372).
// Chunks long log lines so they survive logcat/print truncation (~1024 chars).
// Safe to call from any isolate (including compute() workers) since it uses
// plain synchronous print() rather than debugPrint()'s async throttling.
import 'dart:convert';

int _dlogSeq = 0;

void dlog(String hypothesisId, String message, Map<String, dynamic> data) {
  final batchId = (_dlogSeq++).toString();
  final payload = jsonEncode({
    'hypothesisId': hypothesisId,
    'message': message,
    'data': data,
  });
  const chunkSize = 700;
  final totalParts = (payload.length / chunkSize).ceil().clamp(1, 1 << 30);
  for (var i = 0; i < totalParts; i++) {
    final start = i * chunkSize;
    final end = (start + chunkSize > payload.length) ? payload.length : start + chunkSize;
    final chunk = payload.substring(start, end);
    // ignore: avoid_print
    print('DBG7a9372|$batchId|$i|$totalParts|$chunk');
  }
}
