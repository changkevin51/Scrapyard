import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/core/layout/scrap_layout.dart';

void main() {
  group('ScrapLayout.fromSize', () {
    test('1280×800 landscape tablet is desk with 3/3 columns', () {
      final layout = ScrapLayout.fromSize(const Size(1280, 800));
      expect(layout.mode, ScrapLayoutMode.desk);
      expect(layout.showSidebar, isTrue);
      expect(layout.pileColumns, 3);
      expect(layout.fileColumns, 3);
      expect(layout.deskPadding, 48);
      expect(layout.gridGap, 32);
      expect(layout.pileExtent, 104);
      expect(layout.fileAspectRatio, 1.1);
      expect(layout.compactCards, isFalse);
      expect(layout.usesChatOverlay, isFalse);
      expect(layout.stackSplitVertically, isFalse);
    });

    test('800×1280 portrait tablet is index with 2/2 columns', () {
      final layout = ScrapLayout.fromSize(const Size(800, 1280));
      expect(layout.mode, ScrapLayoutMode.indexStrip);
      expect(layout.showSidebar, isFalse);
      expect(layout.pileColumns, 2);
      expect(layout.fileColumns, 2);
      expect(layout.deskPadding, 24);
      expect(layout.compactCta, isTrue);
      expect(layout.stackSplitVertically, isFalse);
    });

    test('390×844 phone portrait is compact, piles 1, files 2', () {
      final layout = ScrapLayout.fromSize(const Size(390, 844));
      expect(layout.mode, ScrapLayoutMode.compact);
      expect(layout.showSidebar, isFalse);
      expect(layout.pileColumns, 1);
      expect(layout.fileColumns, 2);
      expect(layout.deskPadding, 16);
      expect(layout.compactCards, isTrue);
      expect(layout.usesChatOverlay, isTrue);
      expect(layout.stackSplitVertically, isTrue);
      expect(layout.fileAspectRatio, 0.95);
    });

    test('844×390 phone landscape is compact because height is short', () {
      final layout = ScrapLayout.fromSize(const Size(844, 390));
      expect(layout.mode, ScrapLayoutMode.compact);
      expect(layout.showSidebar, isFalse);
      expect(layout.pileColumns, 1);
      expect(layout.usesChatOverlay, isTrue);
    });

    test('360×640 phone portrait uses 1 file column', () {
      final layout = ScrapLayout.fromSize(const Size(360, 640));
      expect(layout.mode, ScrapLayoutMode.compact);
      expect(layout.fileColumns, 1);
      expect(layout.pileColumns, 1);
      expect(layout.fileAspectRatio, 1.1);
    });

    test('1024×768 old 10" landscape is index, not squished 3-col desk', () {
      final layout = ScrapLayout.fromSize(const Size(1024, 768));
      expect(layout.mode, ScrapLayoutMode.indexStrip);
      expect(layout.showSidebar, isFalse);
      expect(layout.pileColumns, 2);
      expect(layout.fileColumns, 2);
    });

    test('short desktop window 1280×480 is compact, not a overflowing sidebar', () {
      final layout = ScrapLayout.fromSize(const Size(1280, 480));
      expect(layout.mode, ScrapLayoutMode.compact);
      expect(layout.showSidebar, isFalse);
    });

    test('column counts never exceed 3', () {
      final layout = ScrapLayout.fromSize(const Size(2400, 1400));
      expect(layout.fileColumns, lessThanOrEqualTo(ScrapLayout.maxColumns));
      expect(layout.pileColumns, lessThanOrEqualTo(ScrapLayout.maxColumns));
    });
  });
}
