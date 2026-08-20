import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../canvas/domain/models/stroke.dart';
import '../../canvas/presentation/providers/canvas_providers.dart';
import '../domain/models/home_node.dart';
import 'scrap_thumbnail_renderer.dart';

const _androidShare = MethodChannel('scrapyard/share');

Future<void> shareScrapPng(
  WidgetRef ref,
  HomeNode node, {
  Rect? shareOrigin,
}) async {
  final strokes = (await ref.read(canvasRepositoryProvider).loadStrokes(node.id))
      .where((s) => !s.isHidden)
      .toList();
  final bytes = await _renderPng(strokes);

  final dir = await getTemporaryDirectory();
  final shareDir = Directory('${dir.path}/share');
  if (!await shareDir.exists()) {
    await shareDir.create(recursive: true);
  }
  final file = File('${shareDir.path}/tearout_${node.id}.png');
  await file.writeAsBytes(bytes, flush: true);

  try {
    if (Platform.isAndroid) {
      await _androidShare.invokeMethod<void>('shareFile', {
        'path': file.path,
        'mime': 'image/png',
      });
      return;
    }

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'image/png',
          name: 'scrap.png',
        ),
      ],
      sharePositionOrigin: _shareOrigin(shareOrigin),
    );
  } catch (e, st) {
    debugPrint('Tear out share failed: $e\n$st');
    final opened = await OpenFilex.open(file.path, type: 'image/png');
    if (opened.type != ResultType.done) {
      throw Exception(opened.message);
    }
  }
}

Rect _shareOrigin(Rect? shareOrigin) {
  if (shareOrigin == null ||
      shareOrigin.width < 1 ||
      shareOrigin.height < 1) {
    return const Rect.fromLTWH(80, 80, 80, 80);
  }
  return Rect.fromCenter(
    center: shareOrigin.center,
    width: shareOrigin.width.clamp(1, 80),
    height: shareOrigin.height.clamp(1, 80),
  );
}

Future<Uint8List> _renderPng(List<Stroke> strokes) async {
  for (final size in const [Size(800, 720), Size(400, 360)]) {
    try {
      final picture = ScrapThumbnailRenderer.render(strokes, size: size);
      final image =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      try {
        picture.dispose();
      } catch (_) {}
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data != null) {
        return data.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Tear out render ${size.width}x${size.height} failed: $e');
    }
  }
  throw StateError('Could not render scrap');
}

bool isSharePluginMissing(Object error) =>
    error is MissingPluginException ||
    error.toString().contains('MissingPluginException');
