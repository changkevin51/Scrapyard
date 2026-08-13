import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'scrap_thumbnail_renderer.dart';

/// Session-stable cache of first-page PDF rasters for home grid cards.
class PdfThumbnailCache {
  final _images = <String, ui.Image>{};
  final _empty = <String>{};
  final _inflight = <String, Future<ui.Image?>>{};
  final _order = <String>[];
  final _notifiers = <String, ValueNotifier<int>>{};

  static const _maxEntries = 200;
  static const urgentCount = 12;

  ValueNotifier<int> notifierFor(String nodeId) =>
      _notifiers.putIfAbsent(nodeId, () => ValueNotifier(0));

  void _notify(String nodeId) {
    final n = notifierFor(nodeId);
    n.value = n.value + 1;
  }

  ui.Image? peekImage(String nodeId) => _images[nodeId];

  bool hasResolved(String nodeId) =>
      _images.containsKey(nodeId) || _empty.contains(nodeId);

  Future<ui.Image?> loadPicture(String nodeId, String path) {
    if (_images.containsKey(nodeId)) {
      _touch(nodeId);
      return Future.value(_images[nodeId]);
    }
    if (_empty.contains(nodeId)) {
      return Future.value(null);
    }
    final pending = _inflight[nodeId];
    if (pending != null) return pending;

    final future = _fetchAndRender(nodeId, path);
    _inflight[nodeId] = future;
    return future.whenComplete(() => _inflight.remove(nodeId));
  }

  Future<ui.Image?> _fetchAndRender(String nodeId, String path) async {
    try {
      if (!File(path).existsSync()) {
        _empty.add(nodeId);
        _notify(nodeId);
        return null;
      }

      final doc = await PdfDocument.openFile(path);
      try {
        if (doc.pages.isEmpty) {
          _empty.add(nodeId);
          _notify(nodeId);
          return null;
        }

        final page = doc.pages.first;
        const thumb = ScrapThumbnailRenderer.thumbnailSize;
        final scale = min(
          thumb.width / max(page.width, 1),
          thumb.height / max(page.height, 1),
        );
        final fullWidth = max(1.0, page.width * scale);
        final fullHeight = max(1.0, page.height * scale);

        final pdfImage = await page.render(
          width: fullWidth.round(),
          height: fullHeight.round(),
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          backgroundColor: Colors.white,
        );
        if (pdfImage == null) {
          _empty.add(nodeId);
          _notify(nodeId);
          return null;
        }

        try {
          final image = await pdfImage.createImage();
          _put(nodeId, image);
          _notify(nodeId);
          return image;
        } finally {
          pdfImage.dispose();
        }
      } finally {
        await doc.dispose();
      }
    } catch (_) {
      _empty.add(nodeId);
      _notify(nodeId);
      return null;
    }
  }

  Future<void> preload(
    List<(String id, String path)> docs, {
    int urgent = urgentCount,
  }) async {
    if (docs.isEmpty) return;

    final pending = docs.where((d) => !hasResolved(d.$1)).toList();
    if (pending.isEmpty) return;

    final head = pending.take(urgent).toList();
    final tail = pending.skip(urgent).toList();

    for (var i = 0; i < head.length; i += 3) {
      final batch = head.skip(i).take(3).toList();
      await Future.wait(batch.map((d) => loadPicture(d.$1, d.$2)));
      await Future<void>.delayed(Duration.zero);
    }

    for (final d in tail) {
      if (hasResolved(d.$1)) continue;
      await loadPicture(d.$1, d.$2);
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
  }

  void invalidate(String nodeId) {
    _images.remove(nodeId)?.dispose();
    _empty.remove(nodeId);
    _order.remove(nodeId);
    _inflight.remove(nodeId);
    _notify(nodeId);
  }

  void _put(String nodeId, ui.Image image) {
    _empty.remove(nodeId);
    if (_images.containsKey(nodeId)) {
      _touch(nodeId);
      return;
    }
    while (_order.length >= _maxEntries) {
      final evict = _order.removeAt(0);
      _images.remove(evict)?.dispose();
    }
    _images[nodeId] = image;
    _order.add(nodeId);
  }

  void _touch(String nodeId) {
    _order.remove(nodeId);
    _order.add(nodeId);
  }
}
