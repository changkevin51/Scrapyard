import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/annotation_record.dart';

class PDFDocumentRepository {
  static Database? _database;
  final Uuid _uuid = const Uuid();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('koto_pdf.db');
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
      return AnnotationRecord.fromMap(maps[i]);
    });
  }

  Future<void> saveAnnotation(AnnotationRecord record) async {
    final db = await database;
    await db.insert(
      'annotations',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> exportPdfWithAnnotations(String documentId, String outPath) async {
    // Placeholder: Need a native PDF manipulation library to truly flatten custom annotations.
    // For now, this is a mocked endpoint.
  }
}
