/// Visual background pattern for a note page.
///
/// Dimension (fixed vs infinite) is tracked separately via
/// [PageCanvasConfig.isInfinite] — style and canvas size are independent.
enum PageLayout { plain, ruled, dotted, grid }

extension PageLayoutLabels on PageLayout {
  String get chipLabel => switch (this) {
        PageLayout.plain => 'PLAIN',
        PageLayout.ruled => 'RULED',
        PageLayout.dotted => 'DOTTED',
        PageLayout.grid => 'GRID',
      };

  String get displayName => switch (this) {
        PageLayout.plain => 'Plain',
        PageLayout.ruled => 'Ruled',
        PageLayout.dotted => 'Dotted',
        PageLayout.grid => 'Grid',
      };
}

/// Per-note page configuration: background style + optional infinite canvas.
class PageCanvasConfig {
  final PageLayout style;
  final bool isInfinite;

  const PageCanvasConfig({
    required this.style,
    this.isInfinite = false,
  });

  bool get isFinite => !isInfinite;

  PageCanvasConfig copyWith({
    PageLayout? style,
    bool? isInfinite,
  }) =>
      PageCanvasConfig(
        style: style ?? this.style,
        isInfinite: isInfinite ?? this.isInfinite,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageCanvasConfig &&
          style == other.style &&
          isInfinite == other.isInfinite;

  @override
  int get hashCode => Object.hash(style, isInfinite);
}
