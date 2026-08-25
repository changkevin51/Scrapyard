import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Window-size layout for the home desk and phone-use splits.
///
/// Branches on size, not device type, so split-screen, foldables, and
/// resized desktop windows pick the same chrome as a matching phone/tablet.
enum ScrapLayoutMode {
  /// Landscape tablet / desktop: 232px sidebar, 3-column desk.
  desk,

  /// Portrait tablet (and similar widths): top index strip, 2-column desk.
  indexStrip,

  /// Phones, short landscape, or very narrow windows: hamburger + drawer.
  compact,
}

class ScrapLayout {
  static const double deskMinWidth = 1100;
  static const double indexMinWidth = 640;
  static const double compactMaxHeight = 500;
  static const double sidebarWidth = 232;
  static const double minFileCell = 160;
  static const int maxColumns = 3;

  final Size size;
  final ScrapLayoutMode mode;

  const ScrapLayout._(this.size, this.mode);

  factory ScrapLayout.fromSize(Size size) {
    final ScrapLayoutMode mode;
    if (size.height < compactMaxHeight) {
      mode = ScrapLayoutMode.compact;
    } else if (size.width >= deskMinWidth) {
      mode = ScrapLayoutMode.desk;
    } else if (size.width >= indexMinWidth) {
      mode = ScrapLayoutMode.indexStrip;
    } else {
      mode = ScrapLayoutMode.compact;
    }
    return ScrapLayout._(size, mode);
  }

  factory ScrapLayout.of(BuildContext context) {
    return ScrapLayout.fromSize(MediaQuery.sizeOf(context));
  }

  bool get showSidebar => mode == ScrapLayoutMode.desk;

  bool get isDesk => mode == ScrapLayoutMode.desk;

  bool get isIndex => mode == ScrapLayoutMode.indexStrip;

  bool get isCompact => mode == ScrapLayoutMode.compact;

  bool get compactCards => mode == ScrapLayoutMode.compact;

  bool get compactCta => mode != ScrapLayoutMode.desk;

  bool get showCtaCaptions => mode == ScrapLayoutMode.desk;

  /// Overlay Ask only on narrow windows. Wider ones — including short
  /// landscape and resized desktop — reflow the paper beside the panel.
  bool get usesChatOverlay => size.width < indexMinWidth;

  /// PDF | scrap stacks instead of a horizontal split.
  bool get stackSplitVertically => mode == ScrapLayoutMode.compact;

  double get deskPadding {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 48;
      case ScrapLayoutMode.indexStrip:
        return 24;
      case ScrapLayoutMode.compact:
        return 16;
    }
  }

  double get gridGap {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 32;
      case ScrapLayoutMode.indexStrip:
      case ScrapLayoutMode.compact:
        return 16;
    }
  }

  double get pileMainAxisSpacing {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 16;
      case ScrapLayoutMode.indexStrip:
      case ScrapLayoutMode.compact:
        return 12;
    }
  }

  double get pileExtent {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 104;
      case ScrapLayoutMode.indexStrip:
        return 96;
      case ScrapLayoutMode.compact:
        return 88;
    }
  }

  int get pileColumns {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return maxColumns;
      case ScrapLayoutMode.indexStrip:
        return 2;
      case ScrapLayoutMode.compact:
        return 1;
    }
  }

  int get fileColumns {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return maxColumns;
      case ScrapLayoutMode.indexStrip:
        return 2;
      case ScrapLayoutMode.compact:
        final content = size.width - deskPadding * 2;
        final twoColCell = (content - gridGap) / 2;
        return twoColCell >= minFileCell ? 2 : 1;
    }
  }

  double get fileAspectRatio {
    if (mode == ScrapLayoutMode.compact && fileColumns >= 2) return 0.95;
    return 1.1;
  }

  double get subtitleInset {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 56;
      case ScrapLayoutMode.indexStrip:
        return 24;
      case ScrapLayoutMode.compact:
        return 16;
    }
  }

  double get headerTitleSize =>
      mode == ScrapLayoutMode.compact ? 20 : 24;

  double get logoWidth {
    switch (mode) {
      case ScrapLayoutMode.desk:
        return 184;
      case ScrapLayoutMode.indexStrip:
        return 120;
      case ScrapLayoutMode.compact:
        return 100;
    }
  }

  double get drawerWidth => math.min(304, size.width * 0.86);
}
