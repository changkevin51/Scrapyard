import 'dart:convert';
import 'package:flutter/material.dart';

// Recognised shape types — ShapeType.none means raw freeform
enum ShapeType { none, line, circle, oval, rectangle, square, triangle, diamond, star }

class CanvasTable {
  final String id;
  final Offset position;
  final int rows;
  final int cols;
  final double cellWidth;
  final double cellHeight;
  final List<List<String>> cells;

  CanvasTable({
    required this.id,
    required this.position,
    required this.rows,
    required this.cols,
    this.cellWidth = 120.0,
    this.cellHeight = 48.0,
    List<List<String>>? cells,
  }) : cells = cells ?? List.generate(rows, (_) => List.filled(cols, ''));

  CanvasTable copyWithCell(int r, int c, String value) {
    final newCells = cells.map((row) => List<String>.from(row)).toList();
    newCells[r][c] = value;
    return CanvasTable(
      id: id, position: position,
      rows: rows, cols: cols,
      cellWidth: cellWidth, cellHeight: cellHeight,
      cells: newCells,
    );
  }

  CanvasTable copyWithPosition(Offset pos) => CanvasTable(
    id: id, position: pos,
    rows: rows, cols: cols,
    cellWidth: cellWidth, cellHeight: cellHeight,
    cells: cells,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'x': position.dx,
    'y': position.dy,
    'rows': rows,
    'cols': cols,
    'cellWidth': cellWidth,
    'cellHeight': cellHeight,
    'cells': jsonEncode(cells),
  };

  factory CanvasTable.fromMap(Map<String, dynamic> m) => CanvasTable(
    id: m['id'],
    position: Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()),
    rows: m['rows'],
    cols: m['cols'],
    cellWidth: (m['cellWidth'] as num).toDouble(),
    cellHeight: (m['cellHeight'] as num).toDouble(),
    cells: (jsonDecode(m['cells']) as List)
        .map((r) => (r as List).map((c) => c.toString()).toList())
        .toList(),
  );

  String toJson() => jsonEncode(toMap());

  factory CanvasTable.fromJson(String source) =>
      CanvasTable.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class CanvasSticker {
  final String id;
  final Offset position;
  final String content;
  final double size;
  final double rotation;

  const CanvasSticker({
    required this.id,
    required this.position,
    required this.content,
    this.size = 48,
    this.rotation = 0,
  });

  CanvasSticker copyWith({Offset? position, double? size, double? rotation}) =>
      CanvasSticker(
        id: id,
        content: content,
        position: position ?? this.position,
        size: size ?? this.size,
        rotation: rotation ?? this.rotation,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'content': content,
        'size': size,
        'rotation': rotation,
      };

  factory CanvasSticker.fromMap(Map<String, dynamic> m) => CanvasSticker(
        id: m['id'] as String,
        position: Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble()),
        content: m['content'] as String? ?? '',
        size: (m['size'] as num?)?.toDouble() ?? 48,
        rotation: (m['rotation'] as num?)?.toDouble() ?? 0,
      );

  String toJson() => jsonEncode(toMap());

  factory CanvasSticker.fromJson(String source) =>
      CanvasSticker.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
