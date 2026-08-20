import 'dart:io';

import '../../canvas/data/stroke_repository.dart';
import '../../pdf_viewer/data/pdf_document_repository.dart';
import '../domain/models/home_node.dart';

/// Deletes on-disk PDF copies plus stroke/annotation rows for a home node.
class NoteArtifacts {
  static final _strokes = StrokeRepository();
  static final _pdfs = PDFDocumentRepository();

  static Future<void> deleteFor(HomeNode node) async {
    await _strokes.deleteAllForNote(node.id);
    if (node.type == NodeType.document) {
      await _pdfs.deleteAllForDocument(node.id);
      final path = node.externalPath;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  static Future<void> deleteForNoteId(String noteId) {
    return _strokes.deleteAllForNote(noteId);
  }
}
