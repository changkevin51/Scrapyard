import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/pen_engine.dart';
import 'canvas_smart_models.dart';

class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp;

  const StrokePoint({
    required this.x,
    required this.y,
    required this.pressure,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'x': x, 'y': y, 'pressure': pressure, 'timestamp': timestamp,
  };

  factory StrokePoint.fromMap(Map<String, dynamic> map) => StrokePoint(
    x: (map['x'] as num?)?.toDouble() ?? 0,
    y: (map['y'] as num?)?.toDouble() ?? 0,
    pressure: (map['pressure'] as num?)?.toDouble() ?? 1,
    timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
  );
}

class Stroke {
  final String id;
  final List<StrokePoint> points;
  final Color color;
  final double baseWidth;
  final bool isBrush;
  final bool isHighlighter;
  final bool isTape;
  final bool isHidden;
  final bool isStraightLine;

  // Smart shape fields — default to none
  final ShapeType shapeType;
  final List<double> shapeVertices;
  final bool isBeautified; // whether beautification was ON when this stroke was drawn
  final PenStyle penStyle;  // rendering style baked at draw time

  const Stroke({
    required this.id,
    required this.points,
    required this.color,
    required this.baseWidth,
    this.isBrush = false,
    this.isHighlighter = false,
    this.isTape = false,
    this.isHidden = false,
    this.isStraightLine = false,
    this.shapeType = ShapeType.none,
    this.shapeVertices = const [],
    this.isBeautified = false,
    this.penStyle = PenStyle.pen,
  });

  Stroke copyWith({
    List<StrokePoint>? points,
    bool? isHidden,
    bool? isStraightLine,
    ShapeType? shapeType,
    List<double>? shapeVertices,
  }) =>
      Stroke(
        id: id,
        points: points ?? this.points,
        color: color,
        baseWidth: baseWidth,
        isBrush: isBrush,
        isHighlighter: isHighlighter,
        isTape: isTape,
        isStraightLine: isStraightLine ?? this.isStraightLine,
        shapeType: shapeType ?? this.shapeType,
        shapeVertices: shapeVertices ?? this.shapeVertices,
        isBeautified: isBeautified,
        penStyle: penStyle,
        isHidden: isHidden ?? this.isHidden,
      );

  /// Clone this stroke with a new id and point list (e.g. eraser split fragment).
  Stroke withPoints(String newId, List<StrokePoint> newPoints) => Stroke(
        id: newId,
        points: newPoints,
        color: color,
        baseWidth: baseWidth,
        isBrush: isBrush,
        isHighlighter: isHighlighter,
        isTape: isTape,
        isStraightLine: false,
        shapeType: ShapeType.none,
        shapeVertices: const [],
        isBeautified: isBeautified,
        penStyle: penStyle,
        isHidden: isHidden,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'points': points.map((p) => p.toMap()).toList(),
    'color': color.toARGB32(),
    'baseWidth': baseWidth,
    'isBrush': isBrush ? 1 : 0,
    'isHighlighter': isHighlighter ? 1 : 0,
    'isTape': isTape ? 1 : 0,
    'isHidden': isHidden ? 1 : 0,
    'isStraightLine': isStraightLine ? 1 : 0,
    'shapeType': shapeType.name,
    'shapeVertices': shapeVertices,
    'isBeautified': isBeautified ? 1 : 0,
    'penStyle': penStyle.name,
  };

  factory Stroke.fromMap(Map<String, dynamic> map) => Stroke(
    id: map['id'],
    points: (map['points'] as List).map((p) => StrokePoint.fromMap(p)).toList(),
    color: Color(map['color']),
    baseWidth: map['baseWidth'].toDouble(),
    isBrush: map['isBrush'] == 1,
    isHighlighter: map['isHighlighter'] == 1,
    isTape: map['isTape'] == 1,
    isHidden: map['isHidden'] == 1,
    isStraightLine: map['isStraightLine'] == 1,
    shapeType: ShapeType.values.firstWhere(
      (e) => e.name == (map['shapeType'] ?? 'none'),
      orElse: () => ShapeType.none,
    ),
    shapeVertices: map['shapeVertices'] != null
        ? List<double>.from(map['shapeVertices'] as List)
        : [],
    isBeautified: (map['isBeautified'] ?? 0) == 1,
    penStyle: PenStyleInfo.fromPersistedName(map['penStyle'] as String?),
  );

  String toJson() => json.encode(toMap());
  factory Stroke.fromJson(String source) => Stroke.fromMap(json.decode(source));
}
