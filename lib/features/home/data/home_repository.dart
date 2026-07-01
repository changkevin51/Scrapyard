import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/home_node.dart';

class HomeRepository {
  static const String _tableName = 'home_nodes';
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path;
    if (kIsWeb) {
       path = 'koto_home_v2.db';
    } else {
       final dbPath = await getDatabasesPath();
       path = join(dbPath, 'koto_home_v2.db');
    }

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            parent_id TEXT NOT NULL,
            title TEXT NOT NULL,
            type TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            external_path TEXT
          )
        ''');

        // Insert initial Welcome Note setup
        final welcomeNote = HomeNode.create(title: 'Welcome to Koto', type: NodeType.note);
        await db.insert(_tableName, welcomeNote.toMap());

        // Insert sample content
        final japaneseFolder = HomeNode.create(title: 'Japanese 101', type: NodeType.folder);
        await db.insert(_tableName, japaneseFolder.toMap());
        
        final hiraganaNote = HomeNode.create(title: 'Hiragana Practice', type: NodeType.note, parentId: japaneseFolder.id);
        await db.insert(_tableName, hiraganaNote.toMap());
        
        final kanjiNote = HomeNode.create(title: 'Kanji Flashcards', type: NodeType.note, parentId: japaneseFolder.id);
        await db.insert(_tableName, kanjiNote.toMap());

        final physicsFolder = HomeNode.create(title: 'Physics 205', type: NodeType.folder);
        await db.insert(_tableName, physicsFolder.toMap());
        
        final kinematicsNote = HomeNode.create(title: 'Kinematics Equations', type: NodeType.note, parentId: physicsFolder.id);
        await db.insert(_tableName, kinematicsNote.toMap());
      },
    );
  }

  Future<List<HomeNode>> getNodes(String parentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'type ASC, updated_at DESC', // Folders first, then by date
    );

    return maps.map((map) => HomeNode.fromMap(map)).toList();
  }

  Future<void> insertNode(HomeNode node) async {
    final db = await database;
    await db.insert(_tableName, node.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateNode(HomeNode node) async {
    final db = await database;
    await db.update(
      _tableName,
      node.toMap(),
      where: 'id = ?',
      whereArgs: [node.id],
    );
  }

  Future<void> deleteNode(String id) async {
    final db = await database;
    
    // Check if it's a folder, recursively delete contents
    final children = await getNodes(id);
    for (var child in children) {
       await deleteNode(child.id);
    }
    
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
