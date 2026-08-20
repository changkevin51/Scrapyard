import 'dart:convert';

import 'package:flutter/material.dart';

class CanvasTextItem {
  final String id;
  final Offset position;
  final String text;
  final double fontSize;
  /// When true, render as a kraft slip taped onto the scrap (Smelt result).
  final bool taped;
  final String? tapedSteps;

  CanvasTextItem({
    required this.id,
    required this.position,
    this.text = '',
    this.fontSize = 18.0,
    this.taped = false,
    this.tapedSteps,
  });

  CanvasTextItem copyWith({
    Offset? position,
    String? text,
    double? fontSize,
    bool? taped,
    String? tapedSteps,
  }) {
    return CanvasTextItem(
      id: id,
      position: position ?? this.position,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      taped: taped ?? this.taped,
      tapedSteps: tapedSteps ?? this.tapedSteps,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'text': text,
        'fontSize': fontSize,
        'taped': taped,
        'tapedSteps': tapedSteps,
      };

  factory CanvasTextItem.fromMap(Map<String, dynamic> map) => CanvasTextItem(
        id: '${map['id']}',
        position: Offset(
          (map['x'] as num?)?.toDouble() ?? 0,
          (map['y'] as num?)?.toDouble() ?? 0,
        ),
        text: map['text'] as String? ?? '',
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 18.0,
        taped: map['taped'] == true,
        tapedSteps: map['tapedSteps'] as String?,
      );

  String toJson() => json.encode(toMap());

  factory CanvasTextItem.fromJson(String source) =>
      CanvasTextItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
