import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────
// Ink family — Pen Mode vs Brush Mode in the settings panel
// ─────────────────────────────────────────────────────────────────
enum InkFamily { pen, brush, highlighter }

// ─────────────────────────────────────────────────────────────────
// Eraser mode — whole-stroke hide vs area carving
// ─────────────────────────────────────────────────────────────────
enum EraserMode {
  /// Hide any stroke the eraser brush touches.
  stroke,
  /// Carve away ink under the eraser brush (size follows pen width).
  area,
}

extension EraserModeInfo on EraserMode {
  String get label => switch (this) {
        EraserMode.stroke => 'Stroke',
        EraserMode.area => 'Area',
      };

  String get description => switch (this) {
        EraserMode.stroke => 'Remove whole strokes the eraser touches',
        EraserMode.area => 'Erase ink under the brush — size follows pen width',
      };
}

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

  static List<PenStyle> forFamily(InkFamily family) {
    if (family == InkFamily.highlighter) return const [];
    return PenStyle.values.where((s) => s.family == family).toList();
  }

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

  /// Per-tool ink concentration / opacity.
  /// Pen & brush default to 1.0; highlighter defaults to 0.5.
  final Map<InkFamily, double> concentration;

  /// Hold-and-pause shape snapping eligibility for new strokes
  final bool beautify;

  /// Active rendering style
  final PenStyle penStyle;

  /// Per-style pressure/width sensitivity (0–1). Only used by styles
  /// where [PenStyle.hasSensitivity] is true.
  final Map<PenStyle, double> sensitivity;

  /// How the eraser tool removes ink.
  /// Stored nullable so hot-reloaded in-memory settings never crash.
  final EraserMode? eraserMode;

  /// Resolved eraser mode (defaults to stroke).
  EraserMode get eraser => eraserMode ?? EraserMode.stroke;

  static const Map<PenStyle, double> _defaultSensitivity = {
    PenStyle.pen: 0.5,
    PenStyle.pencil: 0.6,
    PenStyle.fountain: 0.55,
    PenStyle.inkBrush: 0.75,
  };

  static const Map<InkFamily, double> _defaultConcentration = {
    InkFamily.pen: 1.0,
    InkFamily.brush: 1.0,
    InkFamily.highlighter: 0.5,
  };

  const PenSettings({
    this.streamline = 0.35,
    this.concentration = _defaultConcentration,
    this.beautify = true,
    this.penStyle = PenStyle.pen,
    this.sensitivity = _defaultSensitivity,
    this.eraserMode = EraserMode.stroke,
  });

  double sensitivityFor(PenStyle style) =>
      sensitivity[style] ?? _defaultSensitivity[style] ?? 0.5;

  double concentrationFor(InkFamily family) =>
      concentration[family] ?? _defaultConcentration[family] ?? 1.0;

  PenSettings copyWith({
    double? streamline,
    Map<InkFamily, double>? concentration,
    bool? beautify,
    PenStyle? penStyle,
    Map<PenStyle, double>? sensitivity,
    EraserMode? eraserMode,
  }) =>
      PenSettings(
        streamline: streamline ?? this.streamline,
        concentration: concentration ?? this.concentration,
        beautify: beautify ?? this.beautify,
        penStyle: penStyle ?? this.penStyle,
        sensitivity: sensitivity ?? this.sensitivity,
        eraserMode: eraserMode ?? this.eraserMode ?? EraserMode.stroke,
      );

  PenSettings withSensitivity(PenStyle style, double value) {
    final next = Map<PenStyle, double>.from(sensitivity)..[style] = value;
    return copyWith(sensitivity: next);
  }

  PenSettings withConcentration(InkFamily family, double value) {
    final next = Map<InkFamily, double>.from(concentration)..[family] = value;
    return copyWith(concentration: next);
  }

  /// Effective color with that tool's concentration baked into alpha.
  /// 1.0 = literal full opacity; lower values fade the stroke.
  Color effectiveColor(Color base, InkFamily family) =>
      base.withValues(alpha: concentrationFor(family).clamp(0.0, 1.0));
}
