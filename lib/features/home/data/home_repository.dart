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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            parent_id TEXT NOT NULL,
            title TEXT NOT NULL,
            type TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            external_path TEXT,
            deleted_at TEXT,
            starred INTEGER NOT NULL DEFAULT 0
          )
        ''');

        final ideasFolder =
            HomeNode.create(title: 'Loose Ideas', type: NodeType.folder);
        await db.insert(_tableName, ideasFolder.toMap());

        final sketchNote = HomeNode.create(
          title: 'Quick Sketch',
          type: NodeType.note,
          parentId: ideasFolder.id,
        );
        await db.insert(_tableName, sketchNote.toMap());

        final doodleNote = HomeNode.create(
          title: 'Margin Doodles',
          type: NodeType.note,
          parentId: ideasFolder.id,
        );
        await db.insert(_tableName, doodleNote.toMap());

        final physicsFolder =
            HomeNode.create(title: 'Physics 205', type: NodeType.folder);
        await db.insert(_tableName, physicsFolder.toMap());

        final kinematicsNote = HomeNode.create(
          title: 'Kinematics Equations',
          type: NodeType.note,
          parentId: physicsFolder.id,
        );
        await db.insert(_tableName, kinematicsNote.toMap());
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN deleted_at TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN starred INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  /// Active (non-deleted) children of [parentId].
  ///
  /// Ordered by recency only so scraps and PDFs interleave; the home
  /// screen splits piles into their own section above files.
  Future<List<HomeNode>> getNodes(String parentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'parent_id = ? AND deleted_at IS NULL',
      whereArgs: [parentId],
      orderBy: 'updated_at DESC',
    );

    return maps.map(HomeNode.fromMap).toList();
  }

  /// Starred scraps and documents (not piles), newest first.
  Future<List<HomeNode>> getStarredNodes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'starred = 1 AND deleted_at IS NULL AND type != ?',
      whereArgs: [NodeType.folder.name],
      orderBy: 'updated_at DESC',
    );
    return maps.map(HomeNode.fromMap).toList();
  }

  Future<void> setStarred(String id, bool starred) async {
    final db = await database;
    await db.update(
      _tableName,
      {'starred': starred ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Children of [parentId] including soft-deleted ones.
  Future<List<HomeNode>> getChildrenAny(String parentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'parent_id = ?',
      whereArgs: [parentId],
    );
    return maps.map(HomeNode.fromMap).toList();
  }

  Future<HomeNode?> getNodeById(String id) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return HomeNode.fromMap(maps.first);
  }

  /// Top-level crushed items (deleted nodes whose parent is not also deleted).
  Future<List<HomeNode>> getDeletedNodes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    final all = maps.map(HomeNode.fromMap).toList();
    final deletedIds = all.map((n) => n.id).toSet();
    return all
        .where(
          (n) => n.parentId == 'root' || !deletedIds.contains(n.parentId),
        )
        .toList();
  }

  Future<void> insertNode(HomeNode node) async {
    final db = await database;
    await db.insert(
      _tableName,
      node.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> touchUpdatedAt(String id) async {
    final db = await database;
    await db.update(
      _tableName,
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft-delete [id] and all active descendants.
  Future<void> softDeleteNode(String id) async {
    final stamp = DateTime.now().toIso8601String();
    await _softDeleteRecursive(id, stamp);
  }

  Future<void> _softDeleteRecursive(String id, String deletedAt) async {
    final children = await getNodes(id);
    for (final child in children) {
      await _softDeleteRecursive(child.id, deletedAt);
    }
    final db = await database;
    await db.update(
      _tableName,
      {'deleted_at': deletedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restore [id] and soft-deleted descendants. Reparents to root if needed.
  Future<void> restoreNode(String id) async {
    final node = await getNodeById(id);
    if (node == null) return;

    var parentId = node.parentId;
    if (parentId != 'root') {
      final parent = await getNodeById(parentId);
      if (parent == null || parent.isDeleted) {
        parentId = 'root';
      }
    }

    await _restoreRecursive(id);
    if (parentId != node.parentId) {
      final db = await database;
      await db.update(
        _tableName,
        {'parent_id': parentId},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _restoreRecursive(String id) async {
    final children = await getChildrenAny(id);
    for (final child in children) {
      if (child.isDeleted) {
        await _restoreRecursive(child.id);
      }
    }
    final db = await database;
    await db.update(
      _tableName,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hard-delete [id] and every descendant (deleted or not).
  Future<void> permanentlyDeleteNode(String id) async {
    final children = await getChildrenAny(id);
    for (final child in children) {
      await permanentlyDeleteNode(child.id);
    }
    final db = await database;
    await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> emptyTrash() async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'deleted_at IS NOT NULL',
    );
  }

  /// Permanently remove items whose [deletedAt] is older than [retention].
  Future<void> purgeExpiredTrash({
    Duration retention = trashRetention,
  }) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(retention).toIso8601String();
    final expired = await db.query(
      _tableName,
      columns: ['id'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    for (final row in expired) {
      await permanentlyDeleteNode(row['id'] as String);
    }
  }

  /// Legacy hard delete — prefer [softDeleteNode] / [permanentlyDeleteNode].
  Future<void> deleteNode(String id) async {
    await permanentlyDeleteNode(id);
  }

  Future<List<HomeNode>> getAllFolders() async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'type = ? AND deleted_at IS NULL',
      whereArgs: [NodeType.folder.name],
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return maps.map(HomeNode.fromMap).toList();
  }

  Future<bool> moveNode(String id, String newParentId) async {
    if (id == newParentId) return false;
    final node = await getNodeById(id);
    if (node == null || node.isDeleted) return false;
    if (node.parentId == newParentId) return true;

    if (node.type == NodeType.folder && newParentId != 'root') {
      var walk = newParentId;
      while (walk != 'root') {
        if (walk == id) return false;
        final parent = await getNodeById(walk);
        if (parent == null) break;
        walk = parent.parentId;
      }
    }

    final db = await database;
    await db.update(
      _tableName,
      {
        'parent_id': newParentId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }
}
