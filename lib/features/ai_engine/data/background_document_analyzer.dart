import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/analysis_hint.dart';

class BackgroundDocumentAnalyzer {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('koto_analyzer.db');
    return _database!;
  }

  static Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  static Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE analysis_hints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_id TEXT NOT NULL,
        text TEXT NOT NULL,
        start_index INTEGER NOT NULL,
        end_index INTEGER NOT NULL
      )
    ''');
  }

  Future<void> analyzeDocument(String documentId, String fullText) async {
    // Run CPU intensive parsing in isolate silently
    final hintsMap = await compute(_parseText, {
      'documentId': documentId,
      'text': fullText,
    });

    final db = await database;
    final batch = db.batch();
    for (final hint in hintsMap) {
      batch.insert('analysis_hints', hint);
    }
    await batch.commit(noResult: true);
  }

  static List<Map<String, dynamic>> _parseText(Map<String, dynamic> args) {
    final String documentId = args['documentId'];
    final String text = args['text'];
    
    final List<Map<String, dynamic>> hints = [];
    final words = text.split(RegExp(r'\s+'));
    int currentIndex = 0;
    
    for (final word in words) {
      // Mock condition: Word considered 'dense' or 'complex'
      if (word.length > 10) {
         final hint = AnalysisHint(
           documentId: documentId,
           text: word,
           startIndex: currentIndex,
           endIndex: currentIndex + word.length,
         );
         hints.add(hint.toMap());
      }
      currentIndex += word.length + 1; // +1 to account for the space removed by split
    }
    return hints;
  }
}
