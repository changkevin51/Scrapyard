import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class TokenRepository {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('koto_tokens.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE tokens (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tokens INTEGER NOT NULL,
          timestamp INTEGER NOT NULL
        )
      ''');
    });
  }

  Future<void> logTokens(int tokens) async {
    final db = await database;
    await db.insert('tokens', {
      'tokens': tokens,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> getDailyTokens() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    
    final result = await db.query(
      'tokens',
      columns: ['SUM(tokens) as total'],
      where: 'timestamp >= ?',
      whereArgs: [startOfDay],
    );
    
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toInt();
    }
    return 0;
  }
}
