import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/stroke.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../data/stroke_repository.dart';
import '../../data/pen_engine.dart';

enum CanvasTool { pen, brush, highlighter, eraser, shape, straightLine, tape, lasso, text, undo, redo }

enum StrokeStyle { solid, dotted, dashed }

final canvasRepositoryProvider = Provider((ref) => StrokeRepository());

final activeCanvasToolProvider = StateProvider<CanvasTool>((ref) => CanvasTool.pen);
// Default ink color: #1C1C1C
final canvasColorProvider = StateProvider<Color>((ref) => const Color(0xFF1C1C1C));
enum PageLayout { plain, ruled, dotted, grid }
enum ToolbarPosition { top, bottom, left, right }

final pageLayoutProvider = StateProvider<PageLayout>((ref) => PageLayout.ruled);
final toolbarPositionProvider = StateProvider<ToolbarPosition>((ref) => ToolbarPosition.top);

enum ToolbarDisplayMode { icons, kanji }
final toolbarDisplayModeProvider = StateProvider<ToolbarDisplayMode>((ref) => ToolbarDisplayMode.icons);

class CanvasTextItem {
  final String id;
  final Offset position;
  final String text;

  CanvasTextItem({required this.id, required this.position, this.text = ''});
  
  CanvasTextItem copyWith({Offset? position, String? text}) {
    return CanvasTextItem(
       id: id,
       position: position ?? this.position,
       text: text ?? this.text,
    );
  }
}

final canvasTextNodesProvider = StateProvider<List<CanvasTextItem>>((ref) => []);
final canvasTablesProvider = StateProvider<List<CanvasTable>>((ref) => []);

class StrokesNotifier extends StateNotifier<List<Stroke>> {
  final StrokeRepository _repository;
  final String _noteId;
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  StrokesNotifier(this._repository, this._noteId) : super([]) {
    _loadStrokes();
  }

  Future<void> _loadStrokes() async {
    final loadedStrokes = await _repository.loadStrokes(_noteId);
    state = loadedStrokes;
    _undoStack.add(List.from(state));
  }

  void addStroke(Stroke stroke) {
    _redoStack.clear(); // Any new action invalidates redo
    if (_undoStack.isEmpty || _undoStack.last != state) {
       _undoStack.add(List.from(state));
    }

    state = [...state, stroke];
    
    // Incrementally save
    _repository.saveStrokes(_noteId, [stroke]);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.from(state));
    state = _undoStack.removeLast();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.from(state));
    state = _redoStack.removeLast();
  }

  /// Replace a stroke in-place (e.g. after shape snapping)
  void replaceStroke(Stroke updated) {
    _undoStack.add(List.from(state));
    state = state.map((s) => s.id == updated.id ? updated : s).toList();
  }

  /// Hide strokes by id (e.g. after OCR → text node conversion)
  void hideStrokes(List<String> ids) {
    _undoStack.add(List.from(state));
    state = state.map((s) => ids.contains(s.id) ? s.copyWith(isHidden: true) : s).toList();
  }
}

final activeNoteIdProvider = StateProvider<String>((ref) => 'mock-note-id');

final strokesProvider = StateNotifierProvider<StrokesNotifier, List<Stroke>>((ref) {
  final repo = ref.watch(canvasRepositoryProvider);
  final noteId = ref.watch(activeNoteIdProvider);
  return StrokesNotifier(repo, noteId);
});

final isPenModeActiveProvider = StateProvider<bool>((ref) => true);
final stylusOnlyModeProvider = StateProvider<bool>((ref) => false);
final strokeWidthModifierProvider = StateProvider<double>((ref) => 1.0);
final strokeStyleProvider = StateProvider<StrokeStyle>((ref) => StrokeStyle.solid);
final penSettingsProvider = StateProvider<PenSettings>((ref) => const PenSettings());

// Selected shape from library (null = freehand draw mode)
final selectedLibraryShapeProvider = StateProvider<ShapeType?>((ref) => null);

// ── Open document tab system ──────────────────────────────────
class OpenedTab {
  final String id;
  final String title;
  final Color accent;
  final String? groupId;

  const OpenedTab({
    required this.id,
    required this.title,
    this.accent = const Color(0xFF6B4C3B),
    this.groupId,
  });

  OpenedTab copyWith({String? groupId}) =>
      OpenedTab(id: id, title: title, accent: accent, groupId: groupId ?? this.groupId);
}

class TabGroup {
  final String id;
  final String name;
  TabGroup({required this.id, required this.name});
}

final openedTabsProvider    = StateProvider<List<OpenedTab>>((ref) => []);
final activeTabIdProvider   = StateProvider<String?>((ref) => null);
final tabGroupsProvider     = StateProvider<List<TabGroup>>((ref) => []);

/// Utility to open a note tab from anywhere in the app.
void openNoteTab(WidgetRef ref, String id, String title, {Color? accent}) {
  final tabs = ref.read(openedTabsProvider);
  if (!tabs.any((t) => t.id == id)) {
    // Pick a consistent color from the palette based on the id hashCode
    const palette = [
      Color(0xFF6B4C3B), Color(0xFF7A9BB5), Color(0xFF8BAF7A),
      Color(0xFFB58590), Color(0xFF9A9590), Color(0xFF7B6B9B),
    ];
    final color = accent ?? palette[id.hashCode.abs() % palette.length];
    ref.read(openedTabsProvider.notifier).state =
        [...tabs, OpenedTab(id: id, title: title, accent: color)];
  }
  ref.read(activeTabIdProvider.notifier).state = id;
  ref.read(activeNoteIdProvider.notifier).state = id;
}
