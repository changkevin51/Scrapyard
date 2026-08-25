import '../../domain/models/canvas_smart_models.dart';
import '../../domain/models/canvas_text_item.dart';
import '../../domain/models/stroke.dart';

class CanvasLayerSnapshot {
  final List<Stroke> strokes;
  final List<CanvasTextItem> texts;
  final List<CanvasTable> tables;

  const CanvasLayerSnapshot({
    required this.strokes,
    required this.texts,
    required this.tables,
  });
}

class CanvasHistoryNotifier {
  final List<CanvasLayerSnapshot> _undo = [];
  final List<CanvasLayerSnapshot> _redo = [];
  bool restoring = false;
  /// Skip listen-based snapshots (load, grouped erase, pan, typing).
  bool ignoreChanges = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get suppressPush => restoring || ignoreChanges;

  void push(CanvasLayerSnapshot snap) {
    if (suppressPush) return;
    _undo.add(snap);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  /// Hidden strokes that no remaining undo/redo snapshot still shows.
  List<String> hiddenIdsSafeToPrune(List<Stroke> current) {
    final neededVisible = <String>{};
    void scan(Iterable<Stroke> strokes) {
      for (final s in strokes) {
        if (!s.isHidden) neededVisible.add(s.id);
      }
    }

    for (final snap in _undo) {
      scan(snap.strokes);
    }
    for (final snap in _redo) {
      scan(snap.strokes);
    }
    return [
      for (final s in current)
        if (s.isHidden && !neededVisible.contains(s.id)) s.id,
    ];
  }

  CanvasLayerSnapshot? popUndo(CanvasLayerSnapshot current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  CanvasLayerSnapshot? popRedo(CanvasLayerSnapshot current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
