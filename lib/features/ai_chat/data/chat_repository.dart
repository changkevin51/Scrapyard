import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/models/chat_conversation.dart';
import '../domain/models/chat_message.dart';

class ChatRepository {
  static const String _conversationsTable = 'conversations';
  static const String _messagesTable = 'messages';
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    String path;
    if (kIsWeb) {
      path = 'koto_chat.db';
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'koto_chat.db');
    }

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_conversationsTable (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            note_id TEXT,
            note_title TEXT,
            model TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_messagesTable (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            suggestions TEXT,
            model_used TEXT,
            model_fallback_note TEXT,
            created_at TEXT NOT NULL,
            is_error INTEGER NOT NULL DEFAULT 0,
            hidden INTEGER NOT NULL DEFAULT 0,
            image TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_conversation ON $_messagesTable(conversation_id)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, _messagesTable, 'image', 'TEXT');
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(
            db,
            _messagesTable,
            'model_fallback_note',
            'TEXT',
          );
        }
      },
    );
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<List<ChatConversation>> listConversations() async {
    final db = await database;
    final maps = await db.query(
      _conversationsTable,
      orderBy: 'updated_at DESC',
    );
    return maps.map(ChatConversation.fromMap).toList();
  }

  Future<ChatConversation?> getConversation(String id) async {
    final db = await database;
    final maps = await db.query(
      _conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ChatConversation.fromMap(maps.first);
  }

  Future<List<ChatMessage>> loadMessages(String conversationId) async {
    final db = await database;
    final maps = await db.query(
      _messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return maps.map(ChatMessage.fromMap).toList();
  }

  Future<void> upsertConversation(ChatConversation conversation) async {
    final db = await database;
    await db.insert(
      _conversationsTable,
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      _messagesTable,
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessage(ChatMessage message) async {
    final db = await database;
    await db.update(
      _messagesTable,
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete(
      _messagesTable,
      where: 'conversation_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      _conversationsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAll() async {
    final db = await database;
    await db.delete(_messagesTable);
    await db.delete(_conversationsTable);
  }

  Future<int> conversationCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_conversationsTable',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
