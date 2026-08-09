import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/models/page_layout.dart';

/// Persisted per-note canvas settings (page layout, home anchor, last view).
class NoteCanvasSettings {
  final String noteId;
  final PageCanvasConfig pageConfig;
  final double? homeX;
  final double? homeY;
  final double? viewX;
  final double? viewY;
  final double? viewScale;

  const NoteCanvasSettings({
    required this.noteId,
    required this.pageConfig,
    this.homeX,
    this.homeY,
    this.viewX,
    this.viewY,
    this.viewScale,
  });

  PageLayout get pageLayout => pageConfig.style;
  bool get isInfinite => pageConfig.isInfinite;

  bool get hasHome => homeX != null && homeY != null;

  NoteCanvasSettings copyWith({
    PageCanvasConfig? pageConfig,
    double? homeX,
    double? homeY,
    double? viewX,
    double? viewY,
    double? viewScale,
    bool clearHome = false,
  }) =>
      NoteCanvasSettings(
        noteId: noteId,
        pageConfig: pageConfig ?? this.pageConfig,
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
  static const prefsKeyDefaultInfinite = 'canvas_default_infinite';
  static const PageLayout defaultPageLayout = PageLayout.grid;
  static const PageCanvasConfig defaultPageConfig = PageCanvasConfig(
    style: defaultPageLayout,
  );

  /// Shared DB schema version (must match [StrokeRepository.dbVersion]).
  static const int dbVersion = 4;

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
      version: dbVersion,
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
        await _createTextNodes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createNoteSettings(db);
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
        if (oldVersion < 4) {
          await _createTextNodes(db);
        }
      },
    );
  }

  static Future<void> _createTextNodes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS text_nodes (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createNoteSettings(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_settings (
        note_id TEXT PRIMARY KEY,
        page_layout TEXT NOT NULL,
        is_infinite INTEGER NOT NULL DEFAULT 0,
        home_x REAL,
        home_y REAL,
        view_x REAL,
        view_y REAL,
        view_scale REAL
      )
    ''');
  }

  /// Split legacy `page_layout = 'infinite'` into style + is_infinite flag.
  static Future<void> _migrateToV3(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(note_settings)');
    final hasInfinite =
        cols.any((c) => (c['name'] as String?) == 'is_infinite');
    if (!hasInfinite) {
      await db.execute(
        'ALTER TABLE note_settings ADD COLUMN is_infinite INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute('''
      UPDATE note_settings
      SET is_infinite = 1, page_layout = 'grid'
      WHERE page_layout = 'infinite'
    ''');
  }

  Future<PageCanvasConfig> loadDefaultPageConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKeyDefaultPageStyle);
    final style = _parseStyle(raw) ?? defaultPageLayout;
    // Legacy: style key stored as "infinite" meant infinite + grid.
    final legacyInfinite = raw == 'infinite';
    final infinite =
        prefs.getBool(prefsKeyDefaultInfinite) ?? legacyInfinite;
    return PageCanvasConfig(style: style, isInfinite: infinite);
  }

  Future<void> saveDefaultPageConfig(PageCanvasConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyDefaultPageStyle, config.style.name);
    await prefs.setBool(prefsKeyDefaultInfinite, config.isInfinite);
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
    final rawLayout = row['page_layout'] as String?;
    final style = _parseStyle(rawLayout) ?? defaultPageLayout;
    final infiniteCol = row['is_infinite'];
    final isInfinite = infiniteCol is int
        ? infiniteCol != 0
        : rawLayout == 'infinite';
    return NoteCanvasSettings(
      noteId: noteId,
      pageConfig: PageCanvasConfig(style: style, isInfinite: isInfinite),
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
        'page_layout': settings.pageConfig.style.name,
        'is_infinite': settings.pageConfig.isInfinite ? 1 : 0,
        'home_x': settings.homeX,
        'home_y': settings.homeY,
        'view_x': settings.viewX,
        'view_y': settings.viewY,
        'view_scale': settings.viewScale,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertPageConfig(String noteId, PageCanvasConfig config) async {
    final existing = await loadNoteSettings(noteId);
    await saveNoteSettings(
      (existing ?? NoteCanvasSettings(noteId: noteId, pageConfig: config))
          .copyWith(pageConfig: config),
    );
  }

  Future<void> upsertHome(String noteId, double x, double y) async {
    final existing = await loadNoteSettings(noteId);
    final config = existing?.pageConfig ??
        const PageCanvasConfig(style: PageLayout.grid, isInfinite: true);
    await saveNoteSettings(
      NoteCanvasSettings(
        noteId: noteId,
        pageConfig: config,
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
    final config = existing?.pageConfig ??
        const PageCanvasConfig(style: PageLayout.grid, isInfinite: true);
    await saveNoteSettings(
      NoteCanvasSettings(
        noteId: noteId,
        pageConfig: config,
        homeX: existing?.homeX,
        homeY: existing?.homeY,
        viewX: x,
        viewY: y,
        viewScale: scale,
      ),
    );
  }

  static PageLayout? _parseStyle(String? raw) {
    if (raw == null) return null;
    // Legacy infinite-as-layout → grid background.
    if (raw == 'infinite') return PageLayout.grid;
    for (final v in PageLayout.values) {
      if (v.name == raw) return v;
    }
    return null;
  }
}
