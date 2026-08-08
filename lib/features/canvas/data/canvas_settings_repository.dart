import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models/page_layout.dart';

/// Persisted per-note canvas settings (page layout, home anchor, last view).
class NoteCanvasSettings {
  final String noteId;
  final PageLayout pageLayout;
  final double? homeX;
  final double? homeY;
  final double? viewX;
  final double? viewY;
  final double? viewScale;

  const NoteCanvasSettings({
    required this.noteId,
    required this.pageLayout,
    this.homeX,
    this.homeY,
    this.viewX,
    this.viewY,
    this.viewScale,
  });

  bool get hasHome => homeX != null && homeY != null;

  NoteCanvasSettings copyWith({
    PageLayout? pageLayout,
    double? homeX,
    double? homeY,
    double? viewX,
    double? viewY,
    double? viewScale,
    bool clearHome = false,
  }) =>
      NoteCanvasSettings(
        noteId: noteId,
        pageLayout: pageLayout ?? this.pageLayout,
        homeX: clearHome ? null : (homeX ?? this.homeX),
        homeY: clearHome ? null : (homeY ?? this.homeY),
        viewX: viewX ?? this.viewX,
        viewY: viewY ?? this.viewY,
        viewScale: viewScale ?? this.viewScale,
      );
}

/// Stores per-note page layout / viewport prefs in the strokes DB, and the
/// app-wide default page style in SharedPreferences.
class CanvasSettingsRepository {
  static const prefsKeyDefaultPageStyle = 'canvas_default_page_style';
  static const PageLayout defaultPageLayout = PageLayout.grid;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openSharedDb();
    return _database!;
  }

  /// Opens the same `koto_strokes.db` used by [StrokeRepository] so both
  /// share the `note_settings` table after the v2 migration.
  Future<Database> _openSharedDb() async {
    String path;
    if (kIsWeb) {
      path = 'koto_strokes.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'koto_strokes.db');
    }

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE strokes (
            id TEXT PRIMARY KEY,
            note_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await _createNoteSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createNoteSettings(db);
        }
      },
    );
  }

  static Future<void> _createNoteSettings(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_settings (
        note_id TEXT PRIMARY KEY,
        page_layout TEXT NOT NULL,
        home_x REAL,
        home_y REAL,
        view_x REAL,
        view_y REAL,
        view_scale REAL
      )
    ''');
  }

  Future<PageLayout> loadDefaultPageLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKeyDefaultPageStyle);
    return _parseLayout(raw) ?? defaultPageLayout;
  }

  Future<void> saveDefaultPageLayout(PageLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyDefaultPageStyle, layout.name);
  }

  Future<NoteCanvasSettings?> loadNoteSettings(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'note_settings',
      where: 'note_id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final layout =
        _parseLayout(row['page_layout'] as String?) ?? defaultPageLayout;
    return NoteCanvasSettings(
      noteId: noteId,
      pageLayout: layout,
      homeX: (row['home_x'] as num?)?.toDouble(),
      homeY: (row['home_y'] as num?)?.toDouble(),
      viewX: (row['view_x'] as num?)?.toDouble(),
      viewY: (row['view_y'] as num?)?.toDouble(),
      viewScale: (row['view_scale'] as num?)?.toDouble(),
    );
  }

  Future<void> saveNoteSettings(NoteCanvasSettings settings) async {
    final db = await database;
    await db.insert(
      'note_settings',
      {
        'note_id': settings.noteId,
        'page_layout': settings.pageLayout.name,
        'home_x': settings.homeX,
        'home_y': settings.homeY,
        'view_x': settings.viewX,
        'view_y': settings.viewY,
        'view_scale': settings.viewScale,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertPageLayout(String noteId, PageLayout layout) async {
    final existing = await loadNoteSettings(noteId);
    await saveNoteSettings(
      (existing ?? NoteCanvasSettings(noteId: noteId, pageLayout: layout))
          .copyWith(pageLayout: layout),
    );
  }

  Future<void> upsertHome(String noteId, double x, double y) async {
    final existing = await loadNoteSettings(noteId);
    final layout = existing?.pageLayout ?? PageLayout.infinite;
    await saveNoteSettings(
      NoteCanvasSettings(
        noteId: noteId,
        pageLayout: layout,
        homeX: x,
        homeY: y,
        viewX: existing?.viewX,
        viewY: existing?.viewY,
        viewScale: existing?.viewScale,
      ),
    );
  }

  Future<void> upsertView(
    String noteId, {
    required double x,
    required double y,
    required double scale,
  }) async {
    final existing = await loadNoteSettings(noteId);
    final layout = existing?.pageLayout ?? PageLayout.infinite;
    await saveNoteSettings(
      NoteCanvasSettings(
        noteId: noteId,
        pageLayout: layout,
        homeX: existing?.homeX,
        homeY: existing?.homeY,
        viewX: x,
        viewY: y,
        viewScale: scale,
      ),
    );
  }

  static PageLayout? _parseLayout(String? raw) {
    if (raw == null) return null;
    for (final v in PageLayout.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
