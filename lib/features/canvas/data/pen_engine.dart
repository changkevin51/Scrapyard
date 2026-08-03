import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// Ink family — Pen Mode vs Brush Mode in the settings panel
// ─────────────────────────────────────────────────────────────────
enum InkFamily { pen, brush }

// ─────────────────────────────────────────────────────────────────
// Pen Style — visual character of the stroke rendering
// ─────────────────────────────────────────────────────────────────
enum PenStyle {
  // Pen family
  pen,         // Slight pressure sensitivity
  ballpoint,   // Constant-width smooth ink (no pressure)
  pencil,      // Pressure-sensitive graphite
  marker,      // Felt-tip, constant width, square caps
  // Brush family
  calligraphy, // Fixed-nib calligraphy: thick downstrokes, thin crossstrokes
  fountain,    // Flexible fountain pen: organic nib-angle variation
  inkBrush,    // Ink brush: high pressure sensitivity, heavy taper
}

extension PenStyleInfo on PenStyle {
  String get label => switch (this) {
    PenStyle.pen         => 'Pen',
    PenStyle.ballpoint   => 'Ballpoint',
    PenStyle.pencil      => 'Pencil',
    PenStyle.marker      => 'Marker',
    PenStyle.calligraphy => 'Calligraphy',
    PenStyle.fountain    => 'Fountain',
    PenStyle.inkBrush    => 'Ink Brush',
  };

  String get description => switch (this) {
    PenStyle.pen         => 'Slight pressure response',
    PenStyle.ballpoint   => 'Uniform width, no pressure',
    PenStyle.pencil      => 'Graphite feel, pressure-sensitive',
    PenStyle.marker      => 'Felt-tip, consistent width',
    PenStyle.calligraphy => 'Thick & thin nib strokes',
    PenStyle.fountain    => 'Flexible nib, organic flow',
    PenStyle.inkBrush    => 'Ink brush, pressure-heavy',
  };

  InkFamily get family => switch (this) {
    PenStyle.pen ||
    PenStyle.ballpoint ||
    PenStyle.pencil ||
    PenStyle.marker =>
      InkFamily.pen,
    PenStyle.calligraphy || PenStyle.fountain || PenStyle.inkBrush =>
      InkFamily.brush,
  };

  /// Whether this style exposes a Sensitivity slider in the settings panel.
  bool get hasSensitivity => switch (this) {
    PenStyle.pen ||
    PenStyle.pencil ||
    PenStyle.fountain ||
    PenStyle.inkBrush =>
      true,
    _ => false,
  };

  static List<PenStyle> forFamily(InkFamily family) =>
      PenStyle.values.where((s) => s.family == family).toList();

  /// Migrate persisted style names from older builds.
  static PenStyle fromPersistedName(String? name) {
    switch (name) {
      case 'normal':
      case 'pen':
        return PenStyle.pen;
      case 'ballpoint':
        return PenStyle.ballpoint;
      case 'chalk':
      case 'pencil':
        return PenStyle.pencil;
      case 'marker':
        return PenStyle.marker;
      case 'calligraphy':
        return PenStyle.calligraphy;
      case 'fountain':
        return PenStyle.fountain;
      case 'brush':
      case 'inkBrush':
        return PenStyle.inkBrush;
      default:
        return PenStyle.pen;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Pen settings model
// ─────────────────────────────────────────────────────────────────
class PenSettings {
  /// perfect_freehand streamline (0 = raw, ~0.65 = max smoothing, no lag)
  final double streamline;

  /// Ink concentration / opacity (0.1 = very light, 1.0 = full)
  final double concentration;

  /// Hold-and-pause shape snapping eligibility for new strokes
  final bool beautify;

  /// Active rendering style
  final PenStyle penStyle;

  /// Per-style pressure/width sensitivity (0–1). Only used by styles
  /// where [PenStyle.hasSensitivity] is true.
  final Map<PenStyle, double> sensitivity;

  static const Map<PenStyle, double> _defaultSensitivity = {
    PenStyle.pen: 0.5,
    PenStyle.pencil: 0.6,
    PenStyle.fountain: 0.55,
    PenStyle.inkBrush: 0.75,
  };

  const PenSettings({
    this.streamline = 0.35,
    this.concentration = 1.0,
    this.beautify = true,
    this.penStyle = PenStyle.pen,
    this.sensitivity = _defaultSensitivity,
  });

  double sensitivityFor(PenStyle style) =>
      sensitivity[style] ?? _defaultSensitivity[style] ?? 0.5;

  PenSettings copyWith({
    double? streamline,
    double? concentration,
    bool? beautify,
    PenStyle? penStyle,
    Map<PenStyle, double>? sensitivity,
  }) =>
      PenSettings(
        streamline: streamline ?? this.streamline,
        concentration: concentration ?? this.concentration,
        beautify: beautify ?? this.beautify,
        penStyle: penStyle ?? this.penStyle,
        sensitivity: sensitivity ?? this.sensitivity,
      );

  PenSettings withSensitivity(PenStyle style, double value) {
    final next = Map<PenStyle, double>.from(sensitivity)..[style] = value;
    return copyWith(sensitivity: next);
  }

  /// Effective color with concentration baked into alpha
  Color effectiveColor(Color base) =>
      base.withValues(alpha: concentration.clamp(0.05, 1.0));
}
