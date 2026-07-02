import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/stroke.dart';

class StrokeRepository {
  static Database? _database;

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
      version: 1,
      onCreate: _createDB,
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
  }

  Future<void> saveStrokes(String noteId, List<Stroke> newStrokes) async {
     final db = await database;
     final batch = db.batch();
     final now = DateTime.now().millisecondsSinceEpoch;

     // Incremental save: we assume 'newStrokes' only contains strokes not yet saved
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
}
