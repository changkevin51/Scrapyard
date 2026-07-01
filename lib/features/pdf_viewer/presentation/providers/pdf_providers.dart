import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/pdf_document_repository.dart';
import '../../domain/models/annotation_record.dart';

enum AnnotationTool { pan, highlight, ink, comment, shape }

final pdfRepositoryProvider = Provider((ref) => PDFDocumentRepository());

final activeToolProvider = StateProvider<AnnotationTool>((ref) => AnnotationTool.pan);

// Default ink color: #1C1C1C
final currentColorProvider = StateProvider<Color>((ref) => const Color(0xFF1C1C1C));

final pdfPageProvider = StateProvider<int>((ref) => 1);
final pdfZoomProvider = StateProvider<double>((ref) => 1.0);
final pdfDocumentIdProvider = StateProvider<String?>((ref) => null);
final isSplitScreenProvider = StateProvider<bool>((ref) => false);

final pageAnnotationsProvider = FutureProvider.family<List<AnnotationRecord>, int>((ref, pageNumber) async {
  final repo = ref.watch(pdfRepositoryProvider);
  final docId = ref.watch(pdfDocumentIdProvider);
  if (docId == null) return [];
  return repo.getAnnotations(docId, pageNumber);
});

class CurrentInkNotifier extends StateNotifier<List<Offset>> {
  CurrentInkNotifier() : super([]);
  
  void addPoint(Offset point) {
    state = [...state, point];
  }
  
  void clear() {
    state = [];
  }
}

final currentInkProvider = StateNotifierProvider<CurrentInkNotifier, List<Offset>>((ref) => CurrentInkNotifier());
