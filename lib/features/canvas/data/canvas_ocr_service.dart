import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models/stroke.dart';

class CanvasOcrResult {
  final String text;
  final Rect boundingBox;

  CanvasOcrResult({required this.text, required this.boundingBox});
}

class CanvasOcrService {
  static const double _maxRasterPx = 1920;

  TextRecognizer? _textRecognizer;

  TextRecognizer _getRecognizer() {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  Future<List<CanvasOcrResult>> recognizeStrokes(
    List<Stroke> strokes,
    BoxConstraints constraints,
  ) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return [];
    final visible = strokes.where((s) => !s.isHidden && s.points.isNotEmpty);
    if (visible.isEmpty) return [];

    File? tempFile;
    try {
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = -double.infinity;
      var maxY = -double.infinity;
      for (final stroke in visible) {
        for (final p in stroke.points) {
          minX = math.min(minX, p.x);
          minY = math.min(minY, p.y);
          maxX = math.max(maxX, p.x);
          maxY = math.max(maxY, p.y);
        }
      }
      if (!minX.isFinite) return [];

      final worldW = math.max(maxX - minX, 1.0);
      final worldH = math.max(maxY - minY, 1.0);
      final capW = math.min(constraints.maxWidth, _maxRasterPx);
      final capH = math.min(constraints.maxHeight, _maxRasterPx);
      final scale = math.min(capW / worldW, capH / worldH).clamp(0.05, 4.0);
      final imgW = (worldW * scale).ceil().clamp(1, _maxRasterPx.toInt());
      final imgH = (worldH * scale).ceil().clamp(1, _maxRasterPx.toInt());

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
        Paint()..color = Colors.white,
      );

      final paint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (final stroke in visible) {
        final path = Path();
        final first = stroke.points.first;
        path.moveTo((first.x - minX) * scale, (first.y - minY) * scale);
        for (var i = 1; i < stroke.points.length; i++) {
          final p = stroke.points[i];
          path.lineTo((p.x - minX) * scale, (p.y - minY) * scale);
        }
        canvas.drawPath(path, paint);
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(imgW, imgH);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (byteData == null) return [];

      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      final recognizedText =
          await _getRecognizer().processImage(InputImage.fromFilePath(tempFile.path));

      return recognizedText.blocks
          .map(
            (block) => CanvasOcrResult(
              text: block.text,
              boundingBox: block.boundingBox,
            ),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('OCR failed: $e');
      return [];
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
