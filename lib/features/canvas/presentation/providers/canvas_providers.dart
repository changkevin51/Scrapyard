import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/stroke.dart';
import '../../domain/models/canvas_smart_models.dart';
import '../../domain/models/canvas_text_item.dart';
import '../../domain/models/page_layout.dart';
import '../../data/stroke_repository.dart';
import '../../data/canvas_settings_repository.dart';
import '../../data/pen_engine.dart';
import '../../data/canvas_ocr_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'canvas_history.dart';

export '../../domain/models/page_layout.dart';
export '../../domain/models/canvas_text_item.dart';
export 'canvas_history.dart';

enum CanvasTool { pen, brush, highlighter, eraser, shape, straightLine, tape, lasso, smelt, text, undo, redo }

/// World-space height of one finite sheet. Grows to fill the editor, never
/// shrinks with the keyboard.
final finitePageHeightProvider = StateProvider<double>((ref) => 900);

/// How many finite sheets are stacked. Always keeps a blank page under ink
/// on the last used page.
final finitePageCountProvider = StateProvider<int>((ref) => 1);

const int kMaxFinitePages = 40;

double suggestedFinitePageHeight({
  required double canvasWidth,
  required double viewportHeight,
}) {
  return math.max(viewportHeight, math.max(canvasWidth * 1.15, 720.0));
}

double finiteContentBottom({
  required List<Stroke> strokes,
  required List<CanvasTextItem> texts,
  required List<CanvasTable> tables,
  double liveY = -1,
}) {
  var maxY = liveY;
  for (final s in strokes) {
    if (s.isHidden || s.points.isEmpty) continue;
    var strokeMax = s.points.first.y;
    for (final p in s.points) {
      if (p.y > strokeMax) strokeMax = p.y;
    }
    strokeMax += s.baseWidth;
    if (strokeMax > maxY) maxY = strokeMax;
  }
  for (final t in texts) {
    final bottom = t.position.dy + (t.taped ? 240.0 : t.fontSize * 2.5);
    if (bottom > maxY) maxY = bottom;
  }
  for (final t in tables) {
    final bottom = t.position.dy + t.rows * t.cellHeight;
    if (bottom > maxY) maxY = bottom;
  }
  return maxY;
}

int finitePagesForBottom(double bottom, double pageHeight) {
  if (pageHeight <= 0) return 1;
  if (bottom < 0) return 1;
  final last = (bottom / pageHeight).floor();
  return math.min(kMaxFinitePages, last + 2);
}

/// Grow the finite scrap if [liveY] or existing marks sit on the last page.
void ensureFinitePages(WidgetRef ref, {double? liveY}) {
  if (ref.read(pageLayoutProvider).isInfinite) return;
  final pageH = ref.read(finitePageHeightProvider);
  final bottom = finiteContentBottom(
    strokes: ref.read(strokesProvider),
    texts: ref.read(canvasTextNodesProvider),
    tables: ref.read(canvasTablesProvider),
    liveY: liveY ?? -1,
  );
  final needed = finitePagesForBottom(bottom, pageH);
  final current = ref.read(finitePageCountProvider);
  if (needed > current) {
    ref.read(finitePageCountProvider.notifier).state = needed;
  }
}

final canvasRepositoryProvider = Provider((ref) => StrokeRepository());

final activeCanvasToolProvider = StateProvider<CanvasTool>((ref) => CanvasTool.pen);

// ── Ink palette defaults ─────────────────────────────────
// Black, Blue, Red, Magenta, Yellow (mark), Green (mark)
const Color inkBlack = Color(0xFF1C1C1C);
const Color inkBlue = Color(0xFF3B6EA8);
const Color inkRed = Color(0xFFC0453A);
const Color inkMagenta = Color(0xFFA84B9B);
const Color markYellow = Color(0xFFF5E05A);
const Color markGreen = Color(0xFF9FD36A);

const List<Color> defaultInkPalette = [
  inkBlack,
  inkBlue,
  inkRed,
  inkMagenta,
  markYellow,
  markGreen,
];

/// Mutable toolbar swatches — custom picks overwrite the slot that opened
/// the picker so the icon stays in sync with the active ink.
final inkPaletteProvider =
    StateProvider<List<Color>>((ref) => List<Color>.of(defaultInkPalette));

/// Which palette slot is ring-selected in the toolbar.
final paletteIndexProvider = StateProvider<int>((ref) => 0);

/// Last colour used by each drawing tool.
final toolColorsProvider = StateProvider<Map<CanvasTool, Color>>(
  (ref) => {
    CanvasTool.pen: inkBlack,
    CanvasTool.brush: inkBlack,
    CanvasTool.highlighter: markYellow,
  },
);

/// Last palette slot used by each drawing tool.
final toolPaletteIndexProvider = StateProvider<Map<CanvasTool, int>>(
  (ref) => {
    CanvasTool.pen: 0,
    CanvasTool.brush: 0,
    CanvasTool.highlighter: 4, // yellow
  },
);

bool isThicknessTool(CanvasTool tool) =>
    tool == CanvasTool.pen ||
    tool == CanvasTool.brush ||
    tool == CanvasTool.highlighter ||
    tool == CanvasTool.eraser ||
    tool == CanvasTool.shape ||
    tool == CanvasTool.straightLine ||
    tool == CanvasTool.tape;

/// Last thickness multiplier used by each drawing tool.
final toolThicknessProvider = StateProvider<Map<CanvasTool, double>>(
  (ref) => {
    CanvasTool.pen: 1.0,
    CanvasTool.brush: 1.0,
    CanvasTool.highlighter: 1.0,
    CanvasTool.eraser: 1.0,
    CanvasTool.shape: 1.0,
    CanvasTool.straightLine: 1.0,
    CanvasTool.tape: 1.0,
  },
);

// Active ink colour (defaults to pen black).
final canvasColorProvider = StateProvider<Color>((ref) => inkBlack);

bool isInkColorTool(CanvasTool tool) =>
    tool == CanvasTool.pen ||
    tool == CanvasTool.brush ||
    tool == CanvasTool.highlighter;

/// Tools that keep their mode when a colour swatch is tapped.
bool keepsToolOnColorSelect(CanvasTool tool) =>
    tool == CanvasTool.pen ||
    tool == CanvasTool.brush ||
    tool == CanvasTool.shape;

/// If the scrap tool is not pen/brush/shape, switch to pen for drawing.
void ensureCanvasToolForColorSelect(WidgetRef ref) {
  final tool = ref.read(activeCanvasToolProvider);
  if (keepsToolOnColorSelect(tool)) return;

  ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.pen;
  ref.read(isPenModeActiveProvider.notifier).state = true;
  ref.read(activeInkFamilyProvider.notifier).state = InkFamily.pen;
  final settings = ref.read(penSettingsProvider);
  if (settings.penStyle.family != InkFamily.pen) {
    ref.read(penSettingsProvider.notifier).state =
        settings.copyWith(penStyle: PenStyle.pen);
  }
  restoreToolThickness(ref, CanvasTool.pen);
}

/// Apply an ink colour to the canvas, current tool memory, and optional swatch.
///
/// [storeFor] overrides which tool colour slot is updated (used by PDF
/// annotation so scrap tool state is left alone).
void applyInkColor(
  WidgetRef ref,
  Color color, {
  int? paletteIndex,
  CanvasTool? storeFor,
}) {
  final c = color.withValues(alpha: 1.0);
  ref.read(canvasColorProvider.notifier).state = c;

  final CanvasTool tool = storeFor ?? ref.read(activeCanvasToolProvider);
  if (isInkColorTool(tool)) {
    ref.read(toolColorsProvider.notifier).update((m) => {...m, tool: c});
  }

  final palette = [...ref.read(inkPaletteProvider)];
  int? idx = paletteIndex;
  if (idx == null) {
    final match = palette.indexWhere((p) => p.toARGB32() == c.toARGB32());
    if (match >= 0) idx = match;
  }

  if (idx != null && idx >= 0 && idx < palette.length) {
    final slot = idx;
    ref.read(paletteIndexProvider.notifier).state = slot;
    if (palette[slot].toARGB32() != c.toARGB32()) {
      palette[slot] = c;
      ref.read(inkPaletteProvider.notifier).state = palette;
    }
    if (isInkColorTool(tool)) {
      ref.read(toolPaletteIndexProvider.notifier).update((m) => {...m, tool: slot});
    }
  }
}

/// Switch the scrap desk back to pen (draw mode + pen ink family).
void selectPenTool(WidgetRef ref) {
  ref.read(activeCanvasToolProvider.notifier).state = CanvasTool.pen;
  ref.read(isPenModeActiveProvider.notifier).state = true;
  ref.read(activeInkFamilyProvider.notifier).state = InkFamily.pen;
  final settings = ref.read(penSettingsProvider);
  if (settings.penStyle.family != InkFamily.pen) {
    ref.read(penSettingsProvider.notifier).state =
        settings.copyWith(penStyle: PenStyle.pen);
  }
  restoreToolColor(ref, CanvasTool.pen);
  restoreToolThickness(ref, CanvasTool.pen);
}

void applyStrokeWidth(WidgetRef ref, double width) {
  ref.read(strokeWidthModifierProvider.notifier).state = width;
  final tool = ref.read(activeCanvasToolProvider);
  if (isThicknessTool(tool)) {
    ref.read(toolThicknessProvider.notifier).update((m) => {...m, tool: width});
  }
}

/// Restore the thickness last used by [tool].
void restoreToolThickness(WidgetRef ref, CanvasTool tool) {
  if (!isThicknessTool(tool)) return;
  final w = ref.read(toolThicknessProvider)[tool] ?? 1.0;
  ref.read(strokeWidthModifierProvider.notifier).state = w;
}

/// Restore the colour last used by [tool] into the active ink + toolbar slot.
void restoreToolColor(WidgetRef ref, CanvasTool tool) {
  if (!isInkColorTool(tool)) return;
  final c = ref.read(toolColorsProvider)[tool] ?? inkBlack;
  final idx = ref.read(toolPaletteIndexProvider)[tool] ?? 0;
  ref.read(canvasColorProvider.notifier).state = c;
  ref.read(paletteIndexProvider.notifier).state = idx;

  final palette = [...ref.read(inkPaletteProvider)];
  if (idx >= 0 && idx < palette.length && palette[idx].toARGB32() != c.toARGB32()) {
    palette[idx] = c;
    ref.read(inkPaletteProvider.notifier).state = palette;
  }
}

enum ToolbarPosition { top, bottom, left, right }

final canvasSettingsRepositoryProvider =
    Provider((ref) => CanvasSettingsRepository());

/// App-wide default for new notes. Loaded from SharedPreferences (ships as Grid).
final defaultPageLayoutProvider =
    StateNotifierProvider<DefaultPageLayoutNotifier, PageCanvasConfig>((ref) {
  return DefaultPageLayoutNotifier(ref.watch(canvasSettingsRepositoryProvider));
});

class DefaultPageLayoutNotifier extends StateNotifier<PageCanvasConfig> {
  DefaultPageLayoutNotifier(this._repo)
      : super(CanvasSettingsRepository.defaultPageConfig) {
    _load();
  }

  final CanvasSettingsRepository _repo;

  Future<void> _load() async {
    state = await _repo.loadDefaultPageConfig();
  }

  Future<void> set(PageCanvasConfig config) async {
    state = config;
    await _repo.saveDefaultPageConfig(config);
  }
}

/// Active note's page config. Persisted per note; falls back to the app default.
final pageLayoutProvider =
    StateNotifierProvider<PageLayoutNotifier, PageCanvasConfig>((ref) {
  return PageLayoutNotifier(ref);
});

class PageLayoutNotifier extends StateNotifier<PageCanvasConfig> {
  PageLayoutNotifier(this._ref)
      : super(_ref.read(defaultPageLayoutProvider)) {
    _loadForActiveNote();
    _ref.listen<String>(activeNoteIdProvider, (_, __) {
      _ref.read(finitePageCountProvider.notifier).state = 1;
      _ref.read(finitePageHeightProvider.notifier).state = 900;
      _loadForActiveNote();
    });
  }

  final Ref _ref;
  String? _loadedNoteId;

  Future<void> _loadForActiveNote() async {
    final noteId = _ref.read(activeNoteIdProvider);
    _loadedNoteId = noteId;
    final repo = _ref.read(canvasSettingsRepositoryProvider);
    final saved = await repo.loadNoteSettings(noteId);
    if (_loadedNoteId != noteId) return;
    if (saved != null) {
      state = saved.pageConfig;
    } else {
      final fallback = _ref.read(defaultPageLayoutProvider);
      state = fallback;
      // Persist so a later default change (or Infinite lock) sticks per note.
      final ephemeral =
          _ref.read(ephemeralNoteIdsProvider).contains(noteId);
      if (!ephemeral) {
        await repo.upsertPageConfig(noteId, fallback);
      }
    }
  }

  Future<void> _persist(PageCanvasConfig config) async {
    state = config;
    final noteId = _ref.read(activeNoteIdProvider);
    final ephemeral =
        _ref.read(ephemeralNoteIdsProvider).contains(noteId);
    if (!ephemeral) {
      await _ref
          .read(canvasSettingsRepositoryProvider)
          .upsertPageConfig(noteId, config);
    }
  }

  /// Change background pattern only (keeps infinite / fixed dimension).
  Future<void> setStyle(PageLayout style) async {
    if (state.style == style) return;
    await _persist(state.copyWith(style: style));
  }

  /// One-way conversion to infinite canvas. Keeps the current background style.
  Future<void> convertToInfinite() async {
    if (state.isInfinite) return;
    await _persist(state.copyWith(isInfinite: true));
  }
}

final toolbarPositionProvider =
    StateProvider<ToolbarPosition>((ref) => ToolbarPosition.top);

class TextNodesNotifier extends StateNotifier<List<CanvasTextItem>> {
  final StrokeRepository _repository;
  final String _noteId;
  final bool _ephemeral;
  final void Function(String noteId)? _onContentChanged;
  final CanvasHistoryNotifier? _history;
  int _loadGen = 0;
  bool _mutatedSinceLoad = false;

  TextNodesNotifier(
    this._repository,
    this._noteId, {
    bool ephemeral = false,
    void Function(String noteId)? onContentChanged,
    CanvasHistoryNotifier? history,
    List<CanvasTextItem>? initial,
  })  : _ephemeral = ephemeral,
        _onContentChanged = onContentChanged,
        _history = history,
        super(initial ?? []) {
    if (!_ephemeral) _load();
  }

  void _markContentChanged() {
    if (!_ephemeral) _onContentChanged?.call(_noteId);
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    _history?.ignoreChanges = true;
    try {
      final loaded = await _repository.loadTextNodes(_noteId);
      if (gen != _loadGen) return;
      if (_mutatedSinceLoad) {
        final existingIds = {for (final n in state) n.id};
        state = [
          ...loaded.where((n) => !existingIds.contains(n.id)),
          ...state,
        ];
      } else {
        state = loaded;
      }
    } catch (e) {
      debugPrint('load text nodes failed: $e');
    } finally {
      if (gen == _loadGen) _history?.ignoreChanges = false;
    }
  }

  void restore(List<CanvasTextItem> items) {
    state = List.from(items);
    if (!_ephemeral) {
      _repository.replaceTextNodes(_noteId, items);
      _onContentChanged?.call(_noteId);
    }
  }

  void add(CanvasTextItem item) {
    _mutatedSinceLoad = true;
    state = [...state, item];
    // Empty placeholders stay in memory only until the user types.
    if (!_ephemeral && (item.text.trim().isNotEmpty || item.taped)) {
      _repository.saveTextNodes(_noteId, [item]);
      _markContentChanged();
    }
  }

  void upsert(CanvasTextItem item) {
    final idx = state.indexWhere((n) => n.id == item.id);
    if (idx < 0) {
      add(item);
      return;
    }
    _history?.ignoreChanges = true;
    final next = List<CanvasTextItem>.from(state);
    next[idx] = item;
    state = next;
    _history?.ignoreChanges = false;
    if (!_ephemeral) {
      if (item.text.trim().isEmpty && !item.taped) {
        _repository.deleteTextNodes([item.id]);
      } else {
        _repository.saveTextNodes(_noteId, [item]);
      }
      _markContentChanged();
    }
  }

  void updateMany(List<CanvasTextItem> updates) {
    if (updates.isEmpty) return;
    final map = {for (final u in updates) u.id: u};
    state = [for (final n in state) map[n.id] ?? n];
    if (!_ephemeral) {
      final persistable = updates
          .where((u) => u.text.trim().isNotEmpty || u.taped)
          .toList();
      if (persistable.isNotEmpty) {
        _repository.saveTextNodes(_noteId, persistable);
        _markContentChanged();
      }
    }
  }

  void replaceAll(List<CanvasTextItem> items) {
    state = List<CanvasTextItem>.from(items);
    if (!_ephemeral) {
      _repository.saveTextNodes(_noteId, items);
      _markContentChanged();
    }
  }

  void deleteIds(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    state = state.where((n) => !idSet.contains(n.id)).toList();
    if (!_ephemeral) {
      _repository.deleteTextNodes(idSet.toList());
      _markContentChanged();
    }
  }
}

final canvasTextNodesProvider =
    StateNotifierProvider<TextNodesNotifier, List<CanvasTextItem>>((ref) {
  final repo = ref.watch(canvasRepositoryProvider);
  final noteId = ref.watch(activeNoteIdProvider);
  final ephemeral = ref.watch(activeNoteIsEphemeralProvider);
  final cached = ephemeral ? ref.read(ephemeralCanvasCacheProvider)[noteId] : null;
  return TextNodesNotifier(
    repo,
    noteId,
    ephemeral: ephemeral,
    initial: cached?.texts,
    history: ref.read(canvasHistoryHolderProvider),
    onContentChanged: (id) {
      ref.read(dirtyNoteIdsProvider.notifier).update((s) => {...s, id});
    },
  );
});

/// Currently editing/selected text node id, or null when none.
final activeTextNodeIdProvider = StateProvider<String?>((ref) => null);

/// When true, the next canvas tap in text mode is consumed (dismiss only —
/// do not create a new text box). Cleared on consume.
final consumeTextCanvasTapProvider = StateProvider<bool>((ref) => false);

/// Latest global rect of the active text editor; note editor scrolls/pans to
/// keep it above the keyboard.
final activeTextGlobalRectProvider = StateProvider<Rect?>((ref) => null);

/// Pointer currently captured by a taped slip. Canvas tools (lasso / smelt /
/// ink) must ignore this pointer until it is released.
final tapedSlipActivePointerProvider = StateProvider<int?>((ref) => null);

final canvasTablesProvider =
    StateNotifierProvider<CanvasTablesNotifier, List<CanvasTable>>((ref) {
  final repo = ref.watch(canvasRepositoryProvider);
  final noteId = ref.watch(activeNoteIdProvider);
  final ephemeral = ref.watch(activeNoteIsEphemeralProvider);
  final cached = ephemeral ? ref.read(ephemeralCanvasCacheProvider)[noteId] : null;
  return CanvasTablesNotifier(
    repo,
    noteId,
    ephemeral: ephemeral,
    initial: cached?.tables,
    history: ref.read(canvasHistoryHolderProvider),
    onContentChanged: (id) {
      ref.read(dirtyNoteIdsProvider.notifier).update((s) => {...s, id});
    },
  );
});

class CanvasTablesNotifier extends StateNotifier<List<CanvasTable>> {
  final StrokeRepository _repository;
  final String _noteId;
  final bool _ephemeral;
  final void Function(String noteId)? _onContentChanged;
  final CanvasHistoryNotifier? _history;
  int _loadGen = 0;
  bool _mutatedSinceLoad = false;

  CanvasTablesNotifier(
    this._repository,
    this._noteId, {
    bool ephemeral = false,
    void Function(String noteId)? onContentChanged,
    CanvasHistoryNotifier? history,
    List<CanvasTable>? initial,
  })  : _ephemeral = ephemeral,
        _onContentChanged = onContentChanged,
        _history = history,
        super(initial ?? []) {
    if (!_ephemeral) _load();
  }

  void _mark() {
    if (!_ephemeral) _onContentChanged?.call(_noteId);
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    _history?.ignoreChanges = true;
    try {
      final loaded = await _repository.loadTables(_noteId);
      if (gen != _loadGen) return;
      if (_mutatedSinceLoad) {
        final existingIds = {for (final t in state) t.id};
        state = [
          ...loaded.where((t) => !existingIds.contains(t.id)),
          ...state,
        ];
      } else {
        state = loaded;
      }
    } catch (e) {
      debugPrint('load tables failed: $e');
    } finally {
      if (gen == _loadGen) _history?.ignoreChanges = false;
    }
  }

  void add(CanvasTable table) {
    _mutatedSinceLoad = true;
    state = [...state, table];
    if (!_ephemeral) {
      _repository.saveTables(_noteId, [table]);
      _mark();
    }
  }

  void upsert(CanvasTable table, {bool checkpoint = false}) {
    final idx = state.indexWhere((t) => t.id == table.id);
    if (idx < 0) {
      add(table);
      return;
    }
    if (!checkpoint) _history?.ignoreChanges = true;
    final next = List<CanvasTable>.from(state);
    next[idx] = table;
    state = next;
    if (!checkpoint) _history?.ignoreChanges = false;
    if (!_ephemeral) {
      _repository.saveTables(_noteId, [table]);
      _mark();
    }
  }

  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
    if (!_ephemeral) {
      _repository.deleteTables([id]);
      _mark();
    }
  }

  void restore(List<CanvasTable> tables) {
    state = List.from(tables);
    if (!_ephemeral) {
      _repository.replaceTables(_noteId, tables);
      _mark();
    }
  }
}

final ocrResultsProvider = StateProvider<List<CanvasOcrResult>>((ref) => []);

class StrokesNotifier extends StateNotifier<List<Stroke>> {
  final StrokeRepository _repository;
  final String _noteId;
  final bool _ephemeral;
  final void Function(String noteId)? _onContentChanged;
  final CanvasHistoryNotifier? _history;
  int _loadGen = 0;
  bool _mutatedSinceLoad = false;

  StrokesNotifier(
    this._repository,
    this._noteId, {
    bool ephemeral = false,
    void Function(String noteId)? onContentChanged,
    CanvasHistoryNotifier? history,
    List<Stroke>? initial,
  })  : _ephemeral = ephemeral,
        _onContentChanged = onContentChanged,
        _history = history,
        super(initial ?? []) {
    if (!_ephemeral) _loadStrokes();
  }

  void _markContentChanged() {
    if (!_ephemeral) _onContentChanged?.call(_noteId);
  }

  void _beginSilent() => _history?.ignoreChanges = true;
  void _endSilent() => _history?.ignoreChanges = false;

  Future<void> _loadStrokes() async {
    final gen = ++_loadGen;
    _beginSilent();
    try {
      final loaded = await _repository.loadStrokes(_noteId);
      if (gen != _loadGen) return;
      if (_mutatedSinceLoad) {
        final existingIds = {for (final s in state) s.id};
        state = [
          ...loaded.where((s) => !existingIds.contains(s.id)),
          ...state,
        ];
      } else {
        state = loaded;
      }
    } catch (e) {
      debugPrint('load strokes failed: $e');
    } finally {
      if (gen == _loadGen) _endSilent();
    }
  }

  void restore(List<Stroke> strokes) {
    state = List.from(strokes);
    if (!_ephemeral) {
      _repository.replaceStrokes(_noteId, strokes);
      _markContentChanged();
    }
  }

  void addStroke(Stroke stroke) {
    _mutatedSinceLoad = true;
    state = [...state, stroke];
    
    // Loose scraps stay in memory only — never filed to disk.
    if (!_ephemeral) {
      _repository.saveStrokes(_noteId, [stroke]);
      _markContentChanged();
    }
  }

  void undo() {
    // Use undoCanvas(ref) — kept as a no-op so older call sites compile
    // until they are updated.
  }

  void redo() {}

  /// Replace a stroke in-place (e.g. after shape snapping)
  void replaceStroke(Stroke updated) {
    state = state.map((s) => s.id == updated.id ? updated : s).toList();
  }

  /// Hide strokes by id (e.g. after OCR → text node conversion)
  void hideStrokes(List<String> ids, {bool pushUndo = true}) {
    if (ids.isEmpty) return;
    if (!pushUndo) _beginSilent();
    final idSet = ids.toSet();
    final updated = <Stroke>[];
    state = state.map((s) {
      if (!idSet.contains(s.id)) return s;
      final hidden = s.copyWith(isHidden: true);
      updated.add(hidden);
      return hidden;
    }).toList();
    if (!_ephemeral && updated.isNotEmpty) {
      _repository.updateStrokes(_noteId, updated);
      _markContentChanged();
    }
    if (!pushUndo) _endSilent();
  }

  void updateStrokes(List<Stroke> updatedStrokes, {bool pushUndo = true}) {
    if (updatedStrokes.isEmpty) return;

    if (!pushUndo) _beginSilent();
    state = state.map((stroke) {
      final replacement = updatedStrokes.where((updated) => updated.id == stroke.id).toList();
      return replacement.isNotEmpty ? replacement.first : stroke;
    }).toList();

    if (!_ephemeral) {
      _repository.updateStrokes(_noteId, updatedStrokes);
      _markContentChanged();
    }
    if (!pushUndo) _endSilent();
  }

  void deleteStrokes(List<String> ids, {bool pushUndo = true}) {
    if (ids.isEmpty) return;

    if (!pushUndo) _beginSilent();
    state = state.where((stroke) => !ids.contains(stroke.id)).toList();
    if (!_ephemeral) {
      _repository.deleteStrokes(ids);
      _markContentChanged();
    }
    if (!pushUndo) _endSilent();
  }

  /// Atomic eraser mutation: hide / update / delete / add fragments in one step.
  /// Set [pushUndo] false to continue an in-progress erase gesture as one undo.
  void applyEraserMutation({
    List<String> hideIds = const [],
    List<String> deleteIds = const [],
    List<Stroke> updates = const [],
    List<Stroke> additions = const [],
    bool pushUndo = true,
  }) {
    if (hideIds.isEmpty &&
        deleteIds.isEmpty &&
        updates.isEmpty &&
        additions.isEmpty) {
      return;
    }
    if (!pushUndo) _beginSilent();
    final hideSet = hideIds.toSet();
    final deleteSet = deleteIds.toSet();
    final updateMap = {for (final s in updates) s.id: s};

    final next = <Stroke>[];
    final persistedUpdates = <Stroke>[];
    for (final s in state) {
      if (deleteSet.contains(s.id)) continue;
      if (updateMap.containsKey(s.id)) {
        final u = updateMap[s.id]!;
        next.add(u);
        persistedUpdates.add(u);
        continue;
      }
      if (hideSet.contains(s.id)) {
        final h = s.copyWith(isHidden: true);
        next.add(h);
        persistedUpdates.add(h);
        continue;
      }
      next.add(s);
    }
    next.addAll(additions);
    state = next;

    if (!_ephemeral) {
      if (persistedUpdates.isNotEmpty) {
        _repository.updateStrokes(_noteId, persistedUpdates);
      }
      if (additions.isNotEmpty) {
        _repository.saveStrokes(_noteId, additions);
      }
      if (deleteIds.isNotEmpty) {
        _repository.deleteStrokes(deleteIds);
      }
      if (persistedUpdates.isNotEmpty ||
          additions.isNotEmpty ||
          deleteIds.isNotEmpty) {
        _markContentChanged();
      }
    }
    if (!pushUndo) _endSilent();
  }
}

final activeNoteIdProvider = StateProvider<String>((ref) => 'mock-note-id');

/// Note ids that exist only in memory — discarded when the editor closes.
final ephemeralNoteIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Filed notes whose canvas content changed during this editor session.
/// Home bumps [HomeNode.updatedAt] from this set when returning from the editor.
final dirtyNoteIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Whether the active note is still in-memory only.
final activeNoteIsEphemeralProvider = Provider<bool>((ref) {
  final id = ref.watch(activeNoteIdProvider);
  return ref.watch(ephemeralNoteIdsProvider).contains(id);
});

final strokesProvider = StateNotifierProvider<StrokesNotifier, List<Stroke>>((ref) {
  final repo = ref.watch(canvasRepositoryProvider);
  final noteId = ref.watch(activeNoteIdProvider);
  final ephemeral = ref.watch(activeNoteIsEphemeralProvider);
  final cached = ephemeral ? ref.read(ephemeralCanvasCacheProvider)[noteId] : null;
  return StrokesNotifier(
    repo,
    noteId,
    ephemeral: ephemeral,
    initial: cached?.strokes,
    history: ref.read(canvasHistoryHolderProvider),
    onContentChanged: (id) {
      ref.read(dirtyNoteIdsProvider.notifier).update((s) => {...s, id});
    },
  );
});

final isPenModeActiveProvider = StateProvider<bool>((ref) => true);

const _prefsKeyPalmReject = 'canvas_palm_rejection';
const _prefsKeyPalmRejectUser = 'canvas_palm_rejection_user';

/// iPad or Android tablet. Used for palm-rejection default only.
bool isTabletDevice() {
  if (kIsWeb) return false;
  final platform = defaultTargetPlatform;
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.android) {
    return false;
  }
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return false;
  final view = views.first;
  final ratio = view.devicePixelRatio;
  if (ratio <= 0) return false;
  return view.physicalSize.shortestSide / ratio >= 600;
}

bool _isStylusKind(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

class StylusOnlyNotifier extends StateNotifier<bool> {
  StylusOnlyNotifier() : super(isTabletDevice()) {
    _load();
  }

  bool _userSet = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _userSet = prefs.getBool(_prefsKeyPalmRejectUser) == true;
    final saved = prefs.getBool(_prefsKeyPalmReject);
    if (_userSet) {
      state = saved ?? false;
    } else {
      state = saved ?? isTabletDevice();
    }
  }

  /// [fromUser] is true for the canvas-settings switch.
  Future<void> setEnabled(bool value, {bool fromUser = true}) async {
    if (fromUser) _userSet = true;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyPalmReject, value);
    if (fromUser) {
      await prefs.setBool(_prefsKeyPalmRejectUser, true);
    }
  }

  /// Turn palm rejection on the first time a stylus is used, unless the user
  /// has already chosen a setting.
  void enableIfStylusDetected(PointerDeviceKind kind) {
    if (!_isStylusKind(kind)) return;
    if (state || _userSet) return;
    setEnabled(true, fromUser: false);
  }
}

final stylusOnlyModeProvider =
    StateNotifierProvider<StylusOnlyNotifier, bool>((ref) {
  return StylusOnlyNotifier();
});
final canvasZoomProvider = StateProvider<double>((ref) => 1.0);
final strokeWidthModifierProvider = StateProvider<double>((ref) => 1.0);
final penSettingsProvider = StateProvider<PenSettings>((ref) => const PenSettings());

/// Sticky Pen-vs-Brush settings family. Survives switching to lasso/eraser/text.
final activeInkFamilyProvider = StateProvider<InkFamily>((ref) => InkFamily.pen);

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
    stashActiveEphemeralCanvas(ref);
    ref.read(activeTabIdProvider.notifier).state = id;
    ref.read(activeNoteIdProvider.notifier).state = id;
    selectPenTool(ref);
}

/// Drop a single loose scrap from memory (tab + ephemeral set).
void discardEphemeralNote(WidgetRef ref, String id) {
  unawaited(ref.read(canvasRepositoryProvider).deleteAllForNote(id));
  final tabs = ref.read(openedTabsProvider).where((t) => t.id != id).toList();
  ref.read(openedTabsProvider.notifier).state = tabs;
  ref.read(ephemeralNoteIdsProvider.notifier).update((ids) {
    final next = {...ids}..remove(id);
    return next;
  });
  ref.read(ephemeralCanvasCacheProvider.notifier).update((m) => {...m}..remove(id));
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
  final repo = ref.read(canvasRepositoryProvider);
  for (final id in ephemeral) {
    unawaited(repo.deleteAllForNote(id));
  }
  // Use the id set — never read OpenedTab.isEphemeral here. Tabs created
  // before a hot reload can have a null field and throw on access.
  final tabs = ref
      .read(openedTabsProvider)
      .where((t) => !ephemeral.contains(t.id))
      .toList();
  ref.read(openedTabsProvider.notifier).state = tabs;
  ref.read(ephemeralNoteIdsProvider.notifier).state = {};
  ref.read(ephemeralCanvasCacheProvider.notifier).update(
        (m) => {...m}..removeWhere((k, _) => ephemeral.contains(k)),
      );
  final activeId = ref.read(activeTabIdProvider);
  if (activeId != null && ephemeral.contains(activeId)) {
    final next = tabs.isNotEmpty ? tabs.last.id : null;
    ref.read(activeTabIdProvider.notifier).state = next;
    if (next != null) {
      ref.read(activeNoteIdProvider.notifier).state = next;
    }
  }
}

class EphemeralCanvasBundle {
  final List<Stroke> strokes;
  final List<CanvasTextItem> texts;
  final List<CanvasTable> tables;

  const EphemeralCanvasBundle({
    required this.strokes,
    required this.texts,
    required this.tables,
  });

  bool get hasInk =>
      strokes.isNotEmpty ||
      texts.any((t) => t.text.trim().isNotEmpty || t.taped) ||
      tables.isNotEmpty;
}

final ephemeralCanvasCacheProvider =
    StateProvider<Map<String, EphemeralCanvasBundle>>((ref) => {});

final canvasHistoryHolderProvider = Provider<CanvasHistoryNotifier>((ref) {
  ref.watch(activeNoteIdProvider);
  return CanvasHistoryNotifier();
});

/// Records undo snapshots after layer changes. Watched by the note editor so
/// listens stay alive. Must not be read from inside those layer providers.
final canvasHistoryCoordinatorProvider = Provider<void>((ref) {
  final hist = ref.watch(canvasHistoryHolderProvider);

  ref.listen<List<Stroke>>(strokesProvider, (prev, next) {
    if (prev == null || hist.suppressPush) return;
    hist.push(
      CanvasLayerSnapshot(
        strokes: List.from(prev),
        texts: List.from(ref.read(canvasTextNodesProvider)),
        tables: List.from(ref.read(canvasTablesProvider)),
      ),
    );
  });
  ref.listen<List<CanvasTextItem>>(canvasTextNodesProvider, (prev, next) {
    if (prev == null || hist.suppressPush) return;
    hist.push(
      CanvasLayerSnapshot(
        strokes: List.from(ref.read(strokesProvider)),
        texts: List.from(prev),
        tables: List.from(ref.read(canvasTablesProvider)),
      ),
    );
  });
  ref.listen<List<CanvasTable>>(canvasTablesProvider, (prev, next) {
    if (prev == null || hist.suppressPush) return;
    hist.push(
      CanvasLayerSnapshot(
        strokes: List.from(ref.read(strokesProvider)),
        texts: List.from(ref.read(canvasTextNodesProvider)),
        tables: List.from(prev),
      ),
    );
  });
});

CanvasLayerSnapshot captureCanvasLayers(WidgetRef ref) => CanvasLayerSnapshot(
      strokes: List.from(ref.read(strokesProvider)),
      texts: List.from(ref.read(canvasTextNodesProvider)),
      tables: List.from(ref.read(canvasTablesProvider)),
    );

void _restoreCanvasSnapshot(WidgetRef ref, CanvasLayerSnapshot snap) {
  final hist = ref.read(canvasHistoryHolderProvider);
  hist.restoring = true;
  ref.read(strokesProvider.notifier).restore(snap.strokes);
  ref.read(canvasTextNodesProvider.notifier).restore(snap.texts);
  ref.read(canvasTablesProvider.notifier).restore(snap.tables);
  hist.restoring = false;
}

void undoCanvas(WidgetRef ref) {
  final hist = ref.read(canvasHistoryHolderProvider);
  final prev = hist.popUndo(captureCanvasLayers(ref));
  if (prev == null) return;
  _restoreCanvasSnapshot(ref, prev);
}

void redoCanvas(WidgetRef ref) {
  final hist = ref.read(canvasHistoryHolderProvider);
  final next = hist.popRedo(captureCanvasLayers(ref));
  if (next == null) return;
  _restoreCanvasSnapshot(ref, next);
}

void stashActiveEphemeralCanvas(WidgetRef ref) {
  final id = ref.read(activeNoteIdProvider);
  if (!ref.read(ephemeralNoteIdsProvider).contains(id)) return;
  ref.read(ephemeralCanvasCacheProvider.notifier).update((m) => {
        ...m,
        id: EphemeralCanvasBundle(
          strokes: List.from(ref.read(strokesProvider)),
          texts: List.from(ref.read(canvasTextNodesProvider)),
          tables: List.from(ref.read(canvasTablesProvider)),
        ),
      });
}

bool activeScrapHasInk(WidgetRef ref) {
  return ref.read(strokesProvider).isNotEmpty ||
      ref
          .read(canvasTextNodesProvider)
          .any((t) => t.text.trim().isNotEmpty || t.taped) ||
      ref.read(canvasTablesProvider).isNotEmpty;
}

bool scrapIdHasInk(WidgetRef ref, String id) {
  if (ref.read(activeNoteIdProvider) == id) return activeScrapHasInk(ref);
  return ref.read(ephemeralCanvasCacheProvider)[id]?.hasInk ?? false;
}

void switchActiveNote(WidgetRef ref, String id) {
  if (ref.read(activeNoteIdProvider) == id) return;
  stashActiveEphemeralCanvas(ref);
  ref.read(activeTabIdProvider.notifier).state = id;
  ref.read(activeNoteIdProvider.notifier).state = id;
  selectPenTool(ref);
}
