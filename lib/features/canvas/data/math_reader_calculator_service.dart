import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../domain/models/canvas_smart_models.dart';
import '../domain/models/stroke.dart';
import '../domain/services/ink_geometry.dart';
import 'math_reader_python.dart';

/// Sidecar recognition: [latex] may be present even when [error] is set
/// (e.g. grammar failure after the CNN already guessed a string).
class MathReaderRecognizeResult {
  const MathReaderRecognizeResult({this.latex, this.error, this.sidecarRev});

  final String? latex;
  final String? error;
  final String? sidecarRev;

  bool get isStaleSidecar => sidecarRev != mathReaderSidecarRev;
}

/// Rasterize expression ink and POST it to the embedded MathReader sidecar.
class MathReaderCalculatorService {
  Future<void>? _ensure;
  bool _ready = false;
  MathReaderSidecar? _sidecar;

  static bool get isPlatformSupported => !kIsWeb;

  bool get isReady => _ready;

  Future<void> ensureModel() {
    if (!isPlatformSupported) return Future.value();
    return _ensure ??= _ensureSidecar();
  }

  Future<void> _ensureSidecar() async {
    try {
      final sidecar = await ensureMathReaderSidecar();
      _sidecar = sidecar;
      _ready = sidecar != null;
      if (!_ready) _ensure = null;
    } catch (e) {
      debugPrint('MathReader sidecar failed: $e');
      _ready = false;
      _sidecar = null;
      _ensure = null;
    }
  }

  /// Recognize [strokes] as a LaTeX expression. Empty latex if not ready.
  Future<MathReaderRecognizeResult> recognizeLatex(List<Stroke> strokes) async {
    final sidecar = _sidecar;
    if (!_ready || sidecar == null || strokes.isEmpty) {
      return const MathReaderRecognizeResult(error: 'sidecar not ready');
    }
    final png = await rasterizeExpression(strokes);
    if (png == null || png.isEmpty) {
      return const MathReaderRecognizeResult(error: 'empty raster');
    }
    final dataUrl = 'data:image/png;base64,${base64Encode(png)}';
    try {
      final resp = await http
          .post(
            sidecar.recognizeUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'image': dataUrl}),
          )
          .timeout(const Duration(seconds: 20));
      final parsed = _parseRecognizeBody(
        resp.body,
        fallbackError: resp.statusCode == 200 ? null : 'HTTP ${resp.statusCode}',
      );
      if (resp.statusCode != 200) {
        debugPrint(
          'MathReader recognize HTTP ${resp.statusCode}: ${resp.body}',
        );
        return parsed;
      }
      debugPrint('MathReader latex=${parsed.latex}');
      return parsed;
    } catch (e) {
      debugPrint('MathReader recognize failed: $e');
      return MathReaderRecognizeResult(error: '$e');
    }
  }

  static MathReaderRecognizeResult _parseRecognizeBody(
    String body, {
    String? fallbackError,
  }) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final latex = data['latex'];
        final error = data['error'];
        final sidecar = data['sidecar'];
        final trimmed = latex is String ? latex.trim() : '';
        final errText = error is String ? error.trim() : '';
        final sidecarRev = sidecar is String ? sidecar : null;
        return MathReaderRecognizeResult(
          latex: trimmed.isEmpty ? null : trimmed,
          error: errText.isEmpty ? fallbackError : errText,
          sidecarRev: sidecarRev,
        );
      }
    } catch (_) {}
    return MathReaderRecognizeResult(error: fallbackError);
  }

  Future<void> dispose() async {
    _ready = false;
    _sidecar = null;
    _ensure = null;
  }
}

/// Crop to stroke bounds, white background, black ~3px ink, modest padding.
Future<Uint8List?> rasterizeExpression(List<Stroke> strokes) async {
  if (strokes.isEmpty) return null;
  final bounds = unionBounds(strokes.map(strokeWorldBounds));
  if (bounds.width < 2 || bounds.height < 2) return null;

  final pad = math.max(24.0, math.max(bounds.width, bounds.height) * 0.14);
  final src = bounds.inflate(pad);
  const targetLong = 640.0;
  final longSide = math.max(src.width, src.height);
  final scale = (targetLong / longSide).clamp(1.0, 6.0);
  final width = (src.width * scale).ceil().clamp(32, 1024);
  final height = (src.height * scale).ceil().clamp(32, 1024);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  canvas.scale(scale, scale);
  canvas.translate(-src.left, -src.top);

  final strokePaint = Paint()
    ..color = Colors.black
    ..strokeWidth = math.max(2.5, 4.0 / scale)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  for (final stroke in strokes) {
    _drawStroke(canvas, stroke, strokePaint);
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes?.buffer.asUint8List();
}

void _drawStroke(Canvas canvas, Stroke stroke, Paint paint) {
  if (stroke.shapeType != ShapeType.none && stroke.shapeVertices.length >= 4) {
    final v = stroke.shapeVertices;
    final path = Path()..moveTo(v[0], v[1]);
    for (var i = 2; i + 1 < v.length; i += 2) {
      path.lineTo(v[i], v[i + 1]);
    }
    if (stroke.shapeType == ShapeType.rectangle ||
        stroke.shapeType == ShapeType.square ||
        stroke.shapeType == ShapeType.circle ||
        stroke.shapeType == ShapeType.oval) {
      path.close();
    }
    canvas.drawPath(path, paint);
    return;
  }
  if (stroke.points.isEmpty) return;
  if (stroke.points.length == 1) {
    final p = stroke.points.first;
    canvas.drawCircle(
      Offset(p.x, p.y),
      paint.strokeWidth / 2,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
    return;
  }
  final path = Path()
    ..moveTo(stroke.points.first.x, stroke.points.first.y);
  for (var i = 1; i < stroke.points.length; i++) {
    path.lineTo(stroke.points[i].x, stroke.points[i].y);
  }
  canvas.drawPath(path, paint);
}
