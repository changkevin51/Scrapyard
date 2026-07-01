import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../domain/models/memory_models.dart';

class MemoryRepository {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('koto_memory.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE study_sessions (
        id TEXT PRIMARY KEY,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        document_ids TEXT NOT NULL,
        total_queries INTEGER NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE query_log (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        selected_text TEXT NOT NULL,
        query_mode TEXT NOT NULL,
        language_detected TEXT NOT NULL,
        subject_tag TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        was_useful INTEGER
      )
    ''');
    
    await db.execute('''
      CREATE TABLE memory_patterns (
        id TEXT PRIMARY KEY,
        pattern_type TEXT NOT NULL,
        subject_tag TEXT NOT NULL,
        rule_json TEXT NOT NULL,
        confidence REAL NOT NULL,
        created_at INTEGER NOT NULL,
        last_applied_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_rules (
        id TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        subject_tag TEXT NOT NULL,
        instruction_text TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        priority INTEGER NOT NULL
      )
    ''');
  }

  // Study Sessions
  Future<void> saveStudySession(StudySession session) async {
    final db = await database;
    await db.insert('study_sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StudySession>> getStudySessions({int limit = 10}) async {
    final db = await database;
    final maps = await db.query('study_sessions', orderBy: 'start_time DESC', limit: limit);
    return maps.map((m) => StudySession.fromMap(m)).toList();
  }

  // Query Logs
  Future<void> saveQueryLog(QueryLog log) async {
    final db = await database;
    await db.insert('query_log', log.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateQueryUsefulness(String logId, bool wasUseful) async {
    final db = await database;
    await db.update('query_log', {'was_useful': wasUseful ? 1 : 0}, where: 'id = ?', whereArgs: [logId]);
  }

  Future<List<QueryLog>> getRecentQueryLogs(int sinceTimestamp) async {
    final db = await database;
    final maps = await db.query('query_log', where: 'timestamp >= ?', whereArgs: [sinceTimestamp]);
    return maps.map((m) => QueryLog.fromMap(m)).toList();
  }

  // Memory Patterns
  Future<void> saveMemoryPattern(MemoryPattern pattern) async {
    final db = await database;
    await db.insert('memory_patterns', pattern.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MemoryPattern>> getMemoryPatterns({String? subjectTag}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (subjectTag != null && subjectTag.isNotEmpty) {
       maps = await db.query('memory_patterns', where: 'subject_tag = ? OR subject_tag = ?', whereArgs: [subjectTag, 'all']);
    } else {
       maps = await db.query('memory_patterns');
    }
    return maps.map((m) => MemoryPattern.fromMap(m)).toList();
  }

  Future<void> clearAutoPatterns() async {
     final db = await database;
     await db.delete('memory_patterns', where: 'pattern_type = ?', whereArgs: [PatternType.auto.name]);
  }

  // User Rules
  Future<void> saveUserRule(UserRule rule) async {
    final db = await database;
    await db.insert('user_rules', rule.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteUserRule(String id) async {
    final db = await database;
    await db.delete('user_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<UserRule>> getUserRules({String? subjectTag}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (subjectTag != null && subjectTag.isNotEmpty) {
       maps = await db.query('user_rules', where: 'subject_tag = ? OR subject_tag = ?', whereArgs: [subjectTag, 'all']);
    } else {
       maps = await db.query('user_rules');
    }
    return maps.map((m) => UserRule.fromMap(m)).toList();
  }
}
