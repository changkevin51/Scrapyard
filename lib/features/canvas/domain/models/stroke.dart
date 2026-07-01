import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/pen_engine.dart';
import '../../presentation/providers/canvas_providers.dart';
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
    x: map['x'].toDouble(),
    y: map['y'].toDouble(),
    pressure: map['pressure'].toDouble(),
    timestamp: map['timestamp'],
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
  final StrokeStyle style;

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
    this.style = StrokeStyle.solid,
    this.shapeType = ShapeType.none,
    this.shapeVertices = const [],
    this.isBeautified = false,
    this.penStyle = PenStyle.normal,
  });

  Stroke copyWith({bool? isHidden}) => Stroke(
    id: id, points: points, color: color, baseWidth: baseWidth,
    isBrush: isBrush, isHighlighter: isHighlighter, isTape: isTape,
    isStraightLine: isStraightLine, style: style,
    shapeType: shapeType, shapeVertices: shapeVertices,
    isBeautified: isBeautified, penStyle: penStyle,
    isHidden: isHidden ?? this.isHidden,
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
    'style': style.name,
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
    style: StrokeStyle.values.firstWhere((e) => e.name == map['style'], orElse: () => StrokeStyle.solid),
    shapeType: ShapeType.values.firstWhere(
      (e) => e.name == (map['shapeType'] ?? 'none'),
      orElse: () => ShapeType.none,
    ),
    shapeVertices: map['shapeVertices'] != null
        ? List<double>.from(map['shapeVertices'] as List)
        : [],
    isBeautified: (map['isBeautified'] ?? 0) == 1,
    penStyle: PenStyle.values.firstWhere(
      (e) => e.name == (map['penStyle'] ?? 'normal'),
      orElse: () => PenStyle.normal,
    ),
  );

  String toJson() => json.encode(toMap());
  factory Stroke.fromJson(String source) => Stroke.fromMap(json.decode(source));
}
