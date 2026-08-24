import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Scrapyard SQLite filenames → leftover Koto names from the previous rebrand.
const _legacyFilenames = {
  'scrapyard_home_v2.db': 'koto_home_v2.db',
  'scrapyard_strokes.db': 'koto_strokes.db',
  'scrapyard_chat.db': 'koto_chat.db',
  'scrapyard_pdf.db': 'koto_pdf.db',
};

/// Resolves a Scrapyard SQLite path, renaming a leftover Koto file once if needed.
Future<String> resolveLocalDatabasePath(String filename) async {
  final legacyFilename = _legacyFilenames[filename];

  if (kIsWeb) {
    if (await databaseExists(filename)) return filename;
    if (legacyFilename != null && await databaseExists(legacyFilename)) {
      return legacyFilename;
    }
    return filename;
  }

  final dbDir = await getDatabasesPath();
  final newPath = p.join(dbDir, filename);
  if (legacyFilename == null) return newPath;

  final legacyPath = p.join(dbDir, legacyFilename);
  if (!await databaseExists(newPath) && await databaseExists(legacyPath)) {
    await _renameSqliteFile(legacyPath, newPath);
  }
  return newPath;
}

Future<void> _renameSqliteFile(String from, String to) async {
  const suffixes = ['', '-wal', '-shm', '-journal'];
  for (final suffix in suffixes) {
    final src = File('$from$suffix');
    if (await src.exists()) {
      await src.rename('$to$suffix');
    }
  }
}
