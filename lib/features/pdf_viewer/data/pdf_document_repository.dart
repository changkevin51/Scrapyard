import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/data/local_database.dart';
import '../domain/models/annotation_record.dart';

class PDFDocumentRepository {
  static Database? _database;
  final Uuid _uuid = const Uuid();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final path = await resolveLocalDatabasePath('scrapyard_pdf.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        title TEXT,
        file_path TEXT,
        added_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE annotations (
        id TEXT PRIMARY KEY,
        document_id TEXT,
        page_number INTEGER,
        type TEXT,
        data TEXT,
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<String> importPdf(String title, String filePath) async {
    final db = await database;
    final String id = _uuid.v4();
    await db.insert('documents', {
      'id': id,
      'title': title,
      'file_path': filePath,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<List<AnnotationRecord>> getAnnotations(String documentId, int pageNumber) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'annotations',
      where: 'document_id = ? AND page_number = ?',
      whereArgs: [documentId, pageNumber],
    );

    return List.generate(maps.length, (i) {
      try {
        return AnnotationRecord.fromMap(maps[i]);
      } catch (_) {
        return null;
      }
    }).whereType<AnnotationRecord>().toList();
  }

  Future<void> saveAnnotation(AnnotationRecord record) async {
    final db = await database;
    await db.insert(
      'annotations',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAnnotation(String id) async {
    final db = await database;
    await db.delete('annotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAnnotations(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'annotations',
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
  }

  Future<void> deleteAllForDocument(String documentId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'annotations',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      await txn.delete(
        'documents',
        where: 'id = ?',
        whereArgs: [documentId],
      );
    });
  }
}
