import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/pdf_providers.dart';
import '../../domain/models/annotation_record.dart';

class AnnotationLayer extends ConsumerStatefulWidget {
  final int pageNumber;
  final String documentId;

  const AnnotationLayer({
    super.key,
    required this.pageNumber,
    required this.documentId,
  });

  @override
  ConsumerState<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends ConsumerState<AnnotationLayer> {
  final _uuid = const Uuid();

  Offset? _startPoint;
  
  void _saveCurrentStroke() {
    final inkPoints = ref.read(currentInkProvider);
    final activeTool = ref.read(activeToolProvider);
    final color = ref.read(currentColorProvider);
    
    if (inkPoints.isEmpty && activeTool != AnnotationTool.comment) return;

    final type = _getAnnotationType(activeTool);
    if (type == null) return;
    
    List<Map<String, double>> convertedPoints = [];
    if (type != AnnotationType.comment) {
        convertedPoints = inkPoints.map((p) => {'dx': p.dx, 'dy': p.dy}).toList();
    } else {
        if (_startPoint != null) {
            convertedPoints = [{'dx': _startPoint!.dx, 'dy': _startPoint!.dy}];
        }
    }

    final record = AnnotationRecord(
      id: _uuid.v4(),
      documentId: widget.documentId,
      pageNumber: widget.pageNumber,
      type: type,
      data: {
        'points': convertedPoints,
        'color': color.value,
        'strokeWidth': activeTool == AnnotationTool.highlight ? 12.0 : 1.5,
      },
    );

    ref.read(pdfRepositoryProvider).saveAnnotation(record).then((_) {
      ref.invalidate(pageAnnotationsProvider(widget.pageNumber));
    });
    
    ref.read(currentInkProvider.notifier).clear();
    _startPoint = null;
  }

  AnnotationType? _getAnnotationType(AnnotationTool tool) {
    switch(tool) {
      case AnnotationTool.highlight: return AnnotationType.highlight;
      case AnnotationTool.ink: return AnnotationType.ink;
      case AnnotationTool.comment: return AnnotationType.comment;
      case AnnotationTool.shape: return AnnotationType.shape;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTool = ref.watch(activeToolProvider);
    final annotationsAsync = ref.watch(pageAnnotationsProvider(widget.pageNumber));
    final inkPoints = ref.watch(currentInkProvider);
    final currentColor = ref.watch(currentColorProvider);

    return GestureDetector(
      behavior: activeTool == AnnotationTool.pan ? HitTestBehavior.deferToChild : HitTestBehavior.opaque,
      onPanStart: (details) {
         if (activeTool == AnnotationTool.pan) return;
         _startPoint = details.localPosition;
         if (activeTool != AnnotationTool.comment) {
             ref.read(currentInkProvider.notifier).clear();
             ref.read(currentInkProvider.notifier).addPoint(details.localPosition);
         }
      },
      onPanUpdate: (details) {
         if (activeTool == AnnotationTool.pan) return;
         if (activeTool != AnnotationTool.comment) {
             ref.read(currentInkProvider.notifier).addPoint(details.localPosition);
         }
      },
      onPanEnd: (details) {
         if (activeTool == AnnotationTool.pan) return;
         _saveCurrentStroke();
      },
      onTapUp: (details) {
         if (activeTool == AnnotationTool.comment) {
             _startPoint = details.localPosition;
             _saveCurrentStroke();
         }
      },
      child: Stack(
        children: [
          // Background layer to capture gestures if opaque
          SizedBox.expand(
            child: ActiveToolAwareContainer(activeTool: activeTool),
          ),
          
          CustomPaint(
            painter: AnnotationPainter(
              annotations: annotationsAsync.value ?? [],
              currentInk: inkPoints,
              currentColor: currentColor,
              currentTool: activeTool,
            ),
            size: Size.infinite,
          ),
        ],
      ),
    );
  }
}

// Allows gestures to pass through if pan panning
class ActiveToolAwareContainer extends StatelessWidget {
  final AnnotationTool activeTool;
  const ActiveToolAwareContainer({super.key, required this.activeTool});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: activeTool == AnnotationTool.pan ? null : Colors.transparent,
    );
  }
}

class AnnotationPainter extends CustomPainter {
  final List<AnnotationRecord> annotations;
  final List<Offset> currentInk;
  final Color currentColor;
  final AnnotationTool currentTool;

  AnnotationPainter({
    required this.annotations,
    required this.currentInk,
    required this.currentColor,
    required this.currentTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Standard records
    for (final record in annotations) {
      if (record.type == AnnotationType.comment) {
         _drawCommentMarker(canvas, record);
      } else {
         _drawPath(canvas, record);
      }
    }

    // Uncommitted current stroke
    if (currentInk.isNotEmpty && currentTool != AnnotationTool.pan && currentTool != AnnotationTool.comment) {
      final paint = Paint()
        ..color = currentTool == AnnotationTool.highlight ? currentColor.withOpacity(0.4) : currentColor
        ..strokeWidth = currentTool == AnnotationTool.highlight ? 12.0 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = currentTool == AnnotationTool.highlight ? StrokeCap.square : StrokeCap.round;

      final path = Path();
      path.moveTo(currentInk.first.dx, currentInk.first.dy);
      for (int i = 1; i < currentInk.length; i++) {
        path.lineTo(currentInk[i].dx, currentInk[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawCommentMarker(Canvas canvas, AnnotationRecord record) {
     final pointsList = record.data['points'] as List<dynamic>?;
     if (pointsList == null || pointsList.isEmpty) return;
     
     final raw = pointsList.first as Map<String, dynamic>;
     final pt = Offset((raw['dx'] as num).toDouble(), (raw['dy'] as num).toDouble());

     final paint = Paint()
      ..color = const Color(0xFF6B4C3B) // Brown marker
      ..style = PaintingStyle.fill;
     
     canvas.drawCircle(pt, 6.0, paint);
  }

  void _drawPath(Canvas canvas, AnnotationRecord record) {
    final pointsList = record.data['points'] as List<dynamic>?;
    if (pointsList == null || pointsList.isEmpty) return;

    final colorVal = record.data['color'] as int? ?? 0xFF1C1C1C;
    final strokeWidth = (record.data['strokeWidth'] as num?)?.toDouble() ?? 1.5;

    final paint = Paint()
      ..color = Color(colorVal)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = record.type == AnnotationType.highlight ? StrokeCap.square : StrokeCap.round;

    final path = Path();
    final firstRaw = pointsList.first as Map<String, dynamic>;
    path.moveTo((firstRaw['dx'] as num).toDouble(), (firstRaw['dy'] as num).toDouble());
    
    for (int i = 1; i < pointsList.length; i++) {
      final raw = pointsList[i] as Map<String, dynamic>;
      path.lineTo((raw['dx'] as num).toDouble(), (raw['dy'] as num).toDouble());
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant AnnotationPainter oldDelegate) {
    return true;
  }
}
