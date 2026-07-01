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
    position: Offset(m['x'].toDouble(), m['y'].toDouble()),
    rows: m['rows'],
    cols: m['cols'],
    cellWidth: m['cellWidth'].toDouble(),
    cellHeight: m['cellHeight'].toDouble(),
    cells: (jsonDecode(m['cells']) as List)
        .map((r) => (r as List).map((c) => c.toString()).toList())
        .toList(),
  );
}
