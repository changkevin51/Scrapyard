import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../canvas/data/stroke_repository.dart';
import 'scrap_thumbnail_renderer.dart';

/// Session-stable cache of rasterized thumbnail images.
///
/// Preload owns loading. Scroll only [peekImage] — no I/O or vector replay.
class ScrapThumbnailCache {
  ScrapThumbnailCache(this._repository);

  final StrokeRepository _repository;
  final _images = <String, ui.Image>{};
  final _empty = <String>{};
  final _inflight = <String, Future<ui.Image?>>{};
  final _order = <String>[];
  final _notifiers = <String, ValueNotifier<int>>{};

  static const _maxEntries = 200;

  /// First N notes in a folder are loaded ASAP; the rest trickle in.
  static const urgentCount = 12;

  /// Per-note tick — only that [ScrapThumbnail] listens, not the whole grid.
  ValueNotifier<int> notifierFor(String noteId) =>
      _notifiers.putIfAbsent(noteId, () => ValueNotifier(0));

  void _notifyNote(String noteId) {
    final n = notifierFor(noteId);
    n.value = n.value + 1;
  }

  /// Sync hit — no I/O, no paint.
  ui.Image? peekImage(String noteId) => _images[noteId];

  bool isEmptyNote(String noteId) => _empty.contains(noteId);

  bool hasResolved(String noteId) =>
      _images.containsKey(noteId) || _empty.contains(noteId);

  bool isLoading(String noteId) => _inflight.containsKey(noteId);

  int get cachedCount => _images.length;

  /// Loads (or returns cached) image. Dedupes concurrent callers.
  Future<ui.Image?> loadPicture(String noteId) {
    if (_images.containsKey(noteId)) {
      _touch(noteId);
      return Future.value(_images[noteId]);
    }
    if (_empty.contains(noteId)) {
      return Future.value(null);
    }
    final pending = _inflight[noteId];
    if (pending != null) return pending;

    final future = _fetchAndRender(noteId);
    _inflight[noteId] = future;
    return future.whenComplete(() => _inflight.remove(noteId));
  }

  Future<ui.Image?> _fetchAndRender(String noteId) async {
    final strokes = await _repository.loadStrokes(noteId);
    final visible = strokes.where((s) => !s.isHidden).toList();
    if (visible.isEmpty) {
      _empty.add(noteId);
      _notifyNote(noteId);
      return null;
    }

    final picture = ScrapThumbnailRenderer.render(visible);
    final w = ScrapThumbnailRenderer.thumbnailSize.width.round();
    final h = ScrapThumbnailRenderer.thumbnailSize.height.round();
    final image = await picture.toImage(w, h);

    _put(noteId, image);
    _notifyNote(noteId);
    return image;
  }

  /// Warm [noteIds]: first [urgentCount] ASAP, then the rest in the background.
  Future<void> preload(
    List<String> noteIds, {
    void Function(String noteId)? onResolved,
    int urgent = urgentCount,
  }) async {
    if (noteIds.isEmpty) return;

    final pending = noteIds.where((id) => !hasResolved(id)).toList();
    if (pending.isEmpty) return;

    final head = pending.take(urgent).toList();
    final tail = pending.skip(urgent).toList();

    for (var i = 0; i < head.length; i += 3) {
      final batch = head.skip(i).take(3).toList();
      await Future.wait(batch.map((id) async {
        await loadPicture(id);
        onResolved?.call(id);
      }));
      await Future<void>.delayed(Duration.zero);
    }

    for (final id in tail) {
      if (hasResolved(id)) continue;
      await loadPicture(id);
      onResolved?.call(id);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  void invalidate(String noteId) {
    _images.remove(noteId)?.dispose();
    _empty.remove(noteId);
    _order.remove(noteId);
    _inflight.remove(noteId);
    _notifyNote(noteId);
  }

  void _put(String noteId, ui.Image image) {
    _empty.remove(noteId);
    if (_images.containsKey(noteId)) {
      _touch(noteId);
      return;
    }
    while (_order.length >= _maxEntries) {
      final evict = _order.removeAt(0);
      _images.remove(evict)?.dispose();
    }
    _images[noteId] = image;
    _order.add(noteId);
  }

  void _touch(String noteId) {
    _order.remove(noteId);
    _order.add(noteId);
  }
}
