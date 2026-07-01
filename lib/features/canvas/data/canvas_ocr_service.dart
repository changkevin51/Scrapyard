import 'dart:io';
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
  TextRecognizer? _textRecognizer;

  TextRecognizer _getRecognizer() {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.japanese);
    return _textRecognizer!;
  }

  Future<List<CanvasOcrResult>> recognizeStrokes(List<Stroke> strokes, BoxConstraints constraints) async {
    // OCR only works on real Android/iOS devices — skip on web/desktop
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return [];
    if (strokes.isEmpty) return [];

    try {
      // 1. Draw strokes to a ui.Picture
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      
      canvas.drawRect(
        Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight),
        Paint()..color = Colors.white,
      );

      for (var stroke in strokes) {
        if (stroke.points.isEmpty) continue;
        final paint = Paint()
          ..color = Colors.black
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final path = Path();
        path.moveTo(stroke.points.first.x, stroke.points.first.y);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].x, stroke.points[i].y);
        }
        canvas.drawPath(path, paint);
      }

      // 2. Extract picture to image
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        constraints.maxWidth.toInt(),
        constraints.maxHeight.toInt()
      );

      // 3. Convert image to PNG bytes
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return [];
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);

      // 4. Process with ML Kit
      final recognizedText = await _getRecognizer().processImage(inputImage);
      
      if (await tempFile.exists()) {
         await tempFile.delete();
      }

      return recognizedText.blocks.map((block) => CanvasOcrResult(
        text: block.text,
        boundingBox: block.boundingBox,
      )).toList();
    } catch (e) {
      debugPrint("OCR failed: $e");
      return [];
    }
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
