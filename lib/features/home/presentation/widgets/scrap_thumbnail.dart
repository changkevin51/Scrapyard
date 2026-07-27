import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../providers/home_providers.dart';

/// Mini content preview of a scrap's handwriting strokes.
///
/// Listens only to this note's cache notifier — scrolling does not rebuild
/// other thumbnails or trigger fetches.
class ScrapThumbnail extends ConsumerStatefulWidget {
  final String noteId;

  const ScrapThumbnail({super.key, required this.noteId});

  @override
  ConsumerState<ScrapThumbnail> createState() => _ScrapThumbnailState();
}

class _ScrapThumbnailState extends ConsumerState<ScrapThumbnail> {
  @override
  Widget build(BuildContext context) {
    final cache = ref.read(scrapThumbnailCacheProvider);
    final listenable = cache.notifierFor(widget.noteId);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final image = cache.peekImage(widget.noteId);

        if (image == null) {
          return const ColoredBox(color: ScrapTheme.background);
        }

        return ColoredBox(
          color: ScrapTheme.background,
          child: RepaintBoundary(
            child: RawImage(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.low,
            ),
          ),
        );
      },
    );
  }
}
