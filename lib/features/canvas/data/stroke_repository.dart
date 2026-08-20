import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/stroke.dart';
import '../domain/models/canvas_text_item.dart';
import '../domain/models/canvas_smart_models.dart';

Future<Database>? _strokesDbFuture;

/// Single connection to `koto_strokes.db` for ink, text, tables, and settings.
Future<Database> openStrokesDatabase() {
  return _strokesDbFuture ??= _openStrokesDatabase();
}

Future<Database> _openStrokesDatabase() async {
  final String path;
  if (kIsWeb) {
    path = 'koto_strokes.db';
  } else {
    final dbPath = await getDatabasesPath();
    path = join(dbPath, 'koto_strokes.db');
  }

  return openDatabase(
    path,
    version: StrokeRepository.dbVersion,
    onCreate: StrokeRepository.createDb,
    onUpgrade: StrokeRepository.upgradeDb,
  );
}

class StrokeRepository {
  /// Shared schema version — keep in sync with [CanvasSettingsRepository.dbVersion].
  static const int dbVersion = 6;

  Future<Database> get database => openStrokesDatabase();

  static Future<void> createDb(Database db, int version) async {
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
  }

  static Future<void> upgradeDb(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
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
    }
    if (oldVersion < 6) {
      await db.execute('DROP TABLE IF EXISTS canvas_stickers');
    }
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

  static Future<void> _createCanvasTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canvas_tables (
        id TEXT PRIMARY KEY,
        note_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _migrateNoteSettingsToV3(Database db) async {
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
    if (newStrokes.isEmpty) return;
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

    final strokes = <Stroke>[];
    for (final row in maps) {
      try {
        strokes.add(Stroke.fromJson(row['data'] as String));
      } catch (e) {
        debugPrint('Skipping corrupt stroke: $e');
      }
    }
    return strokes;
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
    final nodes = <CanvasTextItem>[];
    for (final row in maps) {
      try {
        nodes.add(CanvasTextItem.fromJson(row['data'] as String));
      } catch (e) {
        debugPrint('Skipping corrupt text node: $e');
      }
    }
    return nodes;
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
    await db.transaction((txn) async {
      await txn.delete('strokes', where: 'note_id = ?', whereArgs: [noteId]);
      if (strokes.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = txn.batch();
      for (final stroke in strokes) {
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
    });
  }

  Future<void> replaceTextNodes(
    String noteId,
    List<CanvasTextItem> nodes,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('text_nodes', where: 'note_id = ?', whereArgs: [noteId]);
      if (nodes.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = txn.batch();
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
    });
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
    final tables = <CanvasTable>[];
    for (final row in maps) {
      try {
        tables.add(CanvasTable.fromJson(row['data'] as String));
      } catch (e) {
        debugPrint('Skipping corrupt table: $e');
      }
    }
    return tables;
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
    await db.transaction((txn) async {
      await txn
          .delete('canvas_tables', where: 'note_id = ?', whereArgs: [noteId]);
      if (tables.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = txn.batch();
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
    });
  }

  /// Remove every canvas row for a scrap (used by discard and trash).
  Future<void> deleteAllForNote(String noteId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('strokes', where: 'note_id = ?', whereArgs: [noteId]);
      await txn.delete('text_nodes', where: 'note_id = ?', whereArgs: [noteId]);
      await txn
          .delete('canvas_tables', where: 'note_id = ?', whereArgs: [noteId]);
      await txn
          .delete('note_settings', where: 'note_id = ?', whereArgs: [noteId]);
    });
  }
}
