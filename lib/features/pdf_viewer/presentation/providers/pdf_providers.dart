import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../canvas/domain/models/stroke.dart';
import '../../data/pdf_document_repository.dart';
import '../../domain/models/annotation_record.dart';

enum AnnotationTool { pan, pen, highlighter, eraser, smelt, shape }

final pdfRepositoryProvider = Provider((ref) => PDFDocumentRepository());

final activeToolProvider =
    StateProvider<AnnotationTool>((ref) => AnnotationTool.pan);

final pdfPageProvider = StateProvider<int>((ref) => 1);
final pdfZoomProvider = StateProvider<double>((ref) => 1.0);
final pdfDocumentIdProvider = StateProvider<String?>((ref) => null);
final activePdfPathProvider = StateProvider<String?>((ref) => null);
final activePdfTitleProvider = StateProvider<String?>((ref) => null);
final isSplitScreenProvider = StateProvider<bool>((ref) => false);

/// Page currently receiving an in-progress ink / smelt gesture.
final currentInkPageProvider = StateProvider<int?>((ref) => null);

final pageAnnotationsProvider =
    FutureProvider.family<List<AnnotationRecord>, int>((ref, pageNumber) async {
  final repo = ref.watch(pdfRepositoryProvider);
  final docId = ref.watch(pdfDocumentIdProvider);
  if (docId == null) return [];
  return repo.getAnnotations(docId, pageNumber);
});

class CurrentInkNotifier extends StateNotifier<List<StrokePoint>> {
  CurrentInkNotifier() : super([]);

  void addPoint(StrokePoint point) {
    state = [...state, point];
  }

  void addPoints(List<StrokePoint> points) {
    if (points.isEmpty) return;
    state = [...state, ...points];
  }

  void setPoints(List<StrokePoint> points) {
    state = points;
  }

  void clear() {
    state = [];
  }
}

final currentInkProvider =
    StateNotifierProvider<CurrentInkNotifier, List<StrokePoint>>(
        (ref) => CurrentInkNotifier());

/// Live smelt selection rect in page-local coordinates (null when idle).
final pdfSmeltRectProvider = StateProvider<Rect?>((ref) => null);
