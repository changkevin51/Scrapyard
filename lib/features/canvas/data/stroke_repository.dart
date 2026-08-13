import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/stroke.dart';
import '../domain/models/canvas_text_item.dart';
import '../domain/models/canvas_smart_models.dart';

class StrokeRepository {
  static Database? _database;

  /// Shared schema version — keep in sync with [CanvasSettingsRepository.dbVersion].
  static const int dbVersion = 5;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('koto_strokes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
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
    await _createCanvasTables(db);
    await _createCanvasStickers(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createNoteSettings(db);
    }
    if (oldVersion < 3) {
      await _migrateNoteSettingsToV3(db);
    }
    if (oldVersion < 4) {
      await _createTextNodes(db);
    }
    if (oldVersion < 5) {
      await _createCanvasTables(db);
      await _createCanvasStickers(db);
    }
  }

  Future<void> _createNoteSettings(Database db) async {
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

  Future<void> _createTextNodes(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS text_nodes (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createCanvasTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canvas_tables (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createCanvasStickers(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canvas_stickers (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateNoteSettingsToV3(Database db) async {
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

  Future<void> saveStrokes(String noteId, List<Stroke> newStrokes) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final stroke in newStrokes) {
      batch.insert(
        'strokes',
        {
          'id': stroke.id,
          'note_id': noteId,
          'data': stroke.toJson(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<void> updateStrokes(String noteId, List<Stroke> updatedStrokes) async {
    await saveStrokes(noteId, updatedStrokes);
  }

  Future<List<Stroke>> loadStrokes(String noteId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'strokes',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );

    return List.generate(maps.length, (i) {
      return Stroke.fromJson(maps[i]['data']);
    });
  }

  Future<void> deleteStrokes(List<String> strokeIds) async {
    final db = await database;
    final batch = db.batch();
    for (final id in strokeIds) {
      batch.delete(
        'strokes',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveTextNodes(String noteId, List<CanvasTextItem> nodes) async {
    if (nodes.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final node in nodes) {
      batch.insert(
        'text_nodes',
        {
          'id': node.id,
          'note_id': noteId,
          'data': node.toJson(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CanvasTextItem>> loadTextNodes(String noteId) async {
    final db = await database;
    final maps = await db.query(
      'text_nodes',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) {
      return CanvasTextItem.fromJson(maps[i]['data'] as String);
    });
  }

  Future<void> deleteTextNodes(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete(
        'text_nodes',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceStrokes(String noteId, List<Stroke> strokes) async {
    final db = await database;
    await db.delete('strokes', where: 'note_id = ?', whereArgs: [noteId]);
    if (strokes.isNotEmpty) await saveStrokes(noteId, strokes);
  }

  Future<void> replaceTextNodes(
    String noteId,
    List<CanvasTextItem> nodes,
  ) async {
    final db = await database;
    await db.delete('text_nodes', where: 'note_id = ?', whereArgs: [noteId]);
    if (nodes.isNotEmpty) await saveTextNodes(noteId, nodes);
  }

  Future<void> saveTables(String noteId, List<CanvasTable> tables) async {
    if (tables.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final table in tables) {
      batch.insert(
        'canvas_tables',
        {
          'id': table.id,
          'note_id': noteId,
          'data': table.toJson(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CanvasTable>> loadTables(String noteId) async {
    final db = await database;
    final maps = await db.query(
      'canvas_tables',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) {
      return CanvasTable.fromJson(maps[i]['data'] as String);
    });
  }

  Future<void> deleteTables(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('canvas_tables', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceTables(String noteId, List<CanvasTable> tables) async {
    final db = await database;
    await db.delete('canvas_tables', where: 'note_id = ?', whereArgs: [noteId]);
    if (tables.isNotEmpty) await saveTables(noteId, tables);
  }

  Future<void> saveStickers(String noteId, List<CanvasSticker> stickers) async {
    if (stickers.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final sticker in stickers) {
      batch.insert(
        'canvas_stickers',
        {
          'id': sticker.id,
          'note_id': noteId,
          'data': sticker.toJson(),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CanvasSticker>> loadStickers(String noteId) async {
    final db = await database;
    final maps = await db.query(
      'canvas_stickers',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) {
      return CanvasSticker.fromJson(maps[i]['data'] as String);
    });
  }

  Future<void> deleteStickers(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('canvas_stickers', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> replaceStickers(
    String noteId,
    List<CanvasSticker> stickers,
  ) async {
    final db = await database;
    await db.delete(
      'canvas_stickers',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
    if (stickers.isNotEmpty) await saveStickers(noteId, stickers);
  }
}
