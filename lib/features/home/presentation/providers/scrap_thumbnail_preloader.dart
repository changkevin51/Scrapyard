import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../canvas/presentation/providers/canvas_providers.dart';
import '../../data/scrap_thumbnail_cache.dart';
import '../../domain/models/home_node.dart';

/// Session-long thumbnail picture cache (not auto-disposed).
final scrapThumbnailCacheProvider = Provider(
  (ref) => ScrapThumbnailCache(ref.watch(canvasRepositoryProvider)),
);

/// Coordinates folder warm-up: first rows ASAP, rest in the background.
class ScrapThumbnailPreloader {
  ScrapThumbnailPreloader(this._ref);

  final Ref _ref;
  int _generation = 0;

  ScrapThumbnailCache get _cache => _ref.read(scrapThumbnailCacheProvider);

  /// Start (or restart) warming thumbnails for [nodes] in the current folder.
  void warmFolder(List<HomeNode> nodes) {
    final noteIds = nodes
        .where((n) => n.type == NodeType.note)
        .map((n) => n.id)
        .toList(growable: false);

    final gen = ++_generation;
    unawaited(_run(gen, noteIds));
  }

  Future<void> _run(int gen, List<String> noteIds) async {
    await _cache.preload(noteIds);
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
