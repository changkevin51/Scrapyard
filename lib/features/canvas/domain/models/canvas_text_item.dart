import 'dart:convert';

import 'package:flutter/material.dart';

class CanvasTextItem {
  final String id;
  final Offset position;
  final String text;
  final double fontSize;

  CanvasTextItem({
    required this.id,
    required this.position,
    this.text = '',
    this.fontSize = 18.0,
  });

  CanvasTextItem copyWith({Offset? position, String? text, double? fontSize}) {
    return CanvasTextItem(
      id: id,
      position: position ?? this.position,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'text': text,
        'fontSize': fontSize,
      };

  factory CanvasTextItem.fromMap(Map<String, dynamic> map) => CanvasTextItem(
        id: map['id'] as String,
        position: Offset(
          (map['x'] as num).toDouble(),
          (map['y'] as num).toDouble(),
        ),
        text: map['text'] as String? ?? '',
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 18.0,
      );

  String toJson() => json.encode(toMap());

  factory CanvasTextItem.fromJson(String source) =>
      CanvasTextItem.fromMap(json.decode(source) as Map<String, dynamic>);
}
