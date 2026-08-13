import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/scrapyard_theme.dart';
import '../providers/home_providers.dart';

/// First-page preview of an imported PDF on the home grid.
class PdfThumbnail extends ConsumerStatefulWidget {
  final String nodeId;

  const PdfThumbnail({super.key, required this.nodeId});

  @override
  ConsumerState<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends ConsumerState<PdfThumbnail> {
  @override
  Widget build(BuildContext context) {
    final cache = ref.read(pdfThumbnailCacheProvider);
    final listenable = cache.notifierFor(widget.nodeId);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final image = cache.peekImage(widget.nodeId);

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
