import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../data/pdf_thumbnail_cache.dart';
import '../../data/scrap_thumbnail_cache.dart';
import '../../domain/models/home_node.dart';

/// Session-long thumbnail picture cache (not auto-disposed).
final scrapThumbnailCacheProvider = Provider(
  (ref) => ScrapThumbnailCache(ref.watch(canvasRepositoryProvider)),
);

final pdfThumbnailCacheProvider = Provider((ref) => PdfThumbnailCache());

/// Coordinates folder warm-up: first rows ASAP, rest in the background.
class ScrapThumbnailPreloader {
  ScrapThumbnailPreloader(this._ref);

  final Ref _ref;
  int _generation = 0;

  ScrapThumbnailCache get _cache => _ref.read(scrapThumbnailCacheProvider);
  PdfThumbnailCache get _pdfCache => _ref.read(pdfThumbnailCacheProvider);

  /// Start (or restart) warming thumbnails for [nodes] in the current folder.
  void warmFolder(List<HomeNode> nodes) {
    final noteIds = nodes
        .where((n) => n.type == NodeType.note)
        .map((n) => n.id)
        .toList(growable: false);
    final pdfs = nodes
        .where((n) => n.isPdf)
        .map((n) => (n.id, n.externalPath!))
        .toList(growable: false);

    final gen = ++_generation;
    unawaited(_run(gen, noteIds, pdfs));
  }

  Future<void> _run(
    int gen,
    List<String> noteIds,
    List<(String, String)> pdfs,
  ) async {
    await Future.wait([
      _cache.preload(noteIds),
      _pdfCache.preload(pdfs),
    ]);
    if (gen != _generation) return;
  }

  /// After an edit: drop cache entry and re-render that one note.
  Future<void> refreshNote(String noteId) async {
    _cache.invalidate(noteId);
    await _cache.loadPicture(noteId);
  }
}

final scrapThumbnailPreloaderProvider = Provider<ScrapThumbnailPreloader>((ref) {
  return ScrapThumbnailPreloader(ref);
});
