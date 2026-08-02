import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/stroke.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../data/stroke_repository.dart';
import '../../data/pen_engine.dart';
import '../../data/canvas_ocr_service.dart';

enum CanvasTool { pen, brush, highlighter, eraser, shape, straightLine, tape, lasso, smelt, text, undo, redo }

enum StrokeStyle { solid, dotted, dashed }

final canvasRepositoryProvider = Provider((ref) => StrokeRepository());

final activeCanvasToolProvider = StateProvider<CanvasTool>((ref) => CanvasTool.pen);
// Default ink color: #1C1C1C
final canvasColorProvider = StateProvider<Color>((ref) => const Color(0xFF1C1C1C));
enum PageLayout { plain, ruled, dotted, grid }
enum ToolbarPosition { top, bottom, left, right }

final pageLayoutProvider = StateProvider<PageLayout>((ref) => PageLayout.ruled);
final toolbarPositionProvider = StateProvider<ToolbarPosition>((ref) => ToolbarPosition.top);

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
final ocrResultsProvider = StateProvider<List<CanvasOcrResult>>((ref) => []);

class StrokesNotifier extends StateNotifier<List<Stroke>> {
  final StrokeRepository _repository;
  final String _noteId;
  final bool _ephemeral;
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  StrokesNotifier(this._repository, this._noteId, {bool ephemeral = false})
      : _ephemeral = ephemeral,
        super([]) {
    if (!_ephemeral) _loadStrokes();
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
    
    // Loose scraps stay in memory only — never filed to disk.
    if (!_ephemeral) {
      _repository.saveStrokes(_noteId, [stroke]);
    }
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

  void updateStrokes(List<Stroke> updatedStrokes) {
    if (updatedStrokes.isEmpty) return;

    _undoStack.add(List.from(state));
    state = state.map((stroke) {
      final replacement = updatedStrokes.where((updated) => updated.id == stroke.id).toList();
      return replacement.isNotEmpty ? replacement.first : stroke;
    }).toList();

    if (!_ephemeral) {
      _repository.updateStrokes(_noteId, updatedStrokes);
    }
  }

  void deleteStrokes(List<String> ids) {
    if (ids.isEmpty) return;

    _undoStack.add(List.from(state));
    state = state.where((stroke) => !ids.contains(stroke.id)).toList();
    if (!_ephemeral) {
      _repository.deleteStrokes(ids);
    }
  }
}

final activeNoteIdProvider = StateProvider<String>((ref) => 'mock-note-id');

/// Note ids that exist only in memory — discarded when the editor closes.
final ephemeralNoteIdsProvider = StateProvider<Set<String>>((ref) => {});

final strokesProvider = StateNotifierProvider<StrokesNotifier, List<Stroke>>((ref) {
  final repo = ref.watch(canvasRepositoryProvider);
  final noteId = ref.watch(activeNoteIdProvider);
  // Read (don't watch) so tab cleanup of other scraps won't wipe this canvas.
  // Callers must register the id in [ephemeralNoteIdsProvider] before flipping
  // [activeNoteIdProvider].
  final ephemeral = ref.read(ephemeralNoteIdsProvider).contains(noteId);
  return StrokesNotifier(repo, noteId, ephemeral: ephemeral);
});

final isPenModeActiveProvider = StateProvider<bool>((ref) => true);
final stylusOnlyModeProvider = StateProvider<bool>((ref) => true);
final canvasZoomProvider = StateProvider<double>((ref) => 1.0);
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
  final bool isEphemeral;

  const OpenedTab({
    required this.id,
    required this.title,
    this.accent = const Color(0xFF6B4C3B),
    this.groupId,
    this.isEphemeral = false,
  });

  OpenedTab copyWith({String? groupId, bool? isEphemeral, String? title}) =>
      OpenedTab(
        id: id,
        title: title ?? this.title,
        accent: accent,
        groupId: groupId ?? this.groupId,
        isEphemeral: isEphemeral ?? this.isEphemeral,
      );
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
void openNoteTab(
  WidgetRef ref,
  String id,
  String title, {
  Color? accent,
  bool ephemeral = false,
}) {
  final tabs = ref.read(openedTabsProvider);
  if (!tabs.any((t) => t.id == id)) {
    // Pick a consistent color from the palette based on the id hashCode
    const palette = [
      Color(0xFF6B4C3B), Color(0xFF7A9BB5), Color(0xFF8BAF7A),
      Color(0xFFB58590), Color(0xFF9A9590), Color(0xFF7B6B9B),
    ];
    // Soft pencil grey for loose scraps — reads as "not filed"
    final color = ephemeral
        ? const Color(0xFF9A9590)
        : (accent ?? palette[id.hashCode.abs() % palette.length]);
    ref.read(openedTabsProvider.notifier).state = [
      ...tabs,
      OpenedTab(id: id, title: title, accent: color, isEphemeral: ephemeral),
    ];
  }
  if (ephemeral) {
    ref.read(ephemeralNoteIdsProvider.notifier).update((ids) => {...ids, id});
  }
  ref.read(activeTabIdProvider.notifier).state = id;
  ref.read(activeNoteIdProvider.notifier).state = id;
}

/// Drop a single loose scrap from memory (tab + ephemeral set).
void discardEphemeralNote(WidgetRef ref, String id) {
  final tabs = ref.read(openedTabsProvider).where((t) => t.id != id).toList();
  ref.read(openedTabsProvider.notifier).state = tabs;
  ref.read(ephemeralNoteIdsProvider.notifier).update((ids) {
    final next = {...ids}..remove(id);
    return next;
  });
  final activeId = ref.read(activeTabIdProvider);
  if (activeId == id) {
    final next = tabs.isNotEmpty ? tabs.last.id : null;
    ref.read(activeTabIdProvider.notifier).state = next;
    if (next != null) {
      ref.read(activeNoteIdProvider.notifier).state = next;
    }
  }
}

/// Crush every loose scrap still open — call when leaving the editor desk.
void discardAllEphemeralNotes(WidgetRef ref) {
  final ephemeral = ref.read(ephemeralNoteIdsProvider);
  if (ephemeral.isEmpty) return;
  // Use the id set — never read OpenedTab.isEphemeral here. Tabs created
  // before a hot reload can have a null field and throw on access.
  final tabs = ref
      .read(openedTabsProvider)
      .where((t) => !ephemeral.contains(t.id))
      .toList();
  ref.read(openedTabsProvider.notifier).state = tabs;
  ref.read(ephemeralNoteIdsProvider.notifier).state = {};
  final activeId = ref.read(activeTabIdProvider);
  if (activeId != null && ephemeral.contains(activeId)) {
    final next = tabs.isNotEmpty ? tabs.last.id : null;
    ref.read(activeTabIdProvider.notifier).state = next;
    if (next != null) {
      ref.read(activeNoteIdProvider.notifier).state = next;
    }
  }
}
