/// Visual background / canvas mode for a note.
enum PageLayout { plain, ruled, dotted, grid, infinite }

extension PageLayoutLabels on PageLayout {
  String get chipLabel => switch (this) {
        PageLayout.plain => 'PLAIN',
        PageLayout.ruled => 'RULED',
        PageLayout.dotted => 'DOTTED',
        PageLayout.grid => 'GRID',
        PageLayout.infinite => 'INFINITE',
      };

  String get displayName => switch (this) {
        PageLayout.plain => 'Plain',
        PageLayout.ruled => 'Ruled',
        PageLayout.dotted => 'Dotted',
        PageLayout.grid => 'Grid',
        PageLayout.infinite => 'Infinite',
      };

  bool get isInfinite => this == PageLayout.infinite;

  bool get isFinite => !isInfinite;
}
