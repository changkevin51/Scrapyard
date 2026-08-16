import 'package:flutter_test/flutter_test.dart';
import 'package:scrapyard/features/home/domain/models/home_node.dart';

HomeNode _node({
  required String id,
  required NodeType type,
  String parentId = 'root',
  DateTime? updatedAt,
  String? externalPath,
  DateTime? deletedAt,
  bool starred = false,
  String title = 'Item',
}) {
  return HomeNode(
    id: id,
    parentId: parentId,
    title: title,
    type: type,
    updatedAt: updatedAt ?? DateTime(2026, 8, 16, 12),
    externalPath: externalPath,
    deletedAt: deletedAt,
    starred: starred,
  );
}

void main() {
  group('HomeNode starred persistence', () {
    test('toMap / fromMap round-trips starred', () {
      final node = _node(
        id: 'n1',
        type: NodeType.note,
        starred: true,
        title: 'Pinned scrap',
      );
      final restored = HomeNode.fromMap(node.toMap());
      expect(restored.starred, isTrue);
      expect(restored.id, 'n1');
      expect(restored.title, 'Pinned scrap');
    });

    test('fromMap treats missing starred as false', () {
      final node = HomeNode.fromMap({
        'id': 'n2',
        'parent_id': 'root',
        'title': 'Old row',
        'type': 'note',
        'updated_at': DateTime(2026, 1, 1).toIso8601String(),
        'external_path': null,
        'deleted_at': null,
      });
      expect(node.starred, isFalse);
    });

    test('copyWith can toggle starred without dropping other fields', () {
      final node = _node(
        id: 'pdf1',
        type: NodeType.document,
        externalPath: '/docs/notes.pdf',
        starred: false,
      );
      final starred = node.copyWith(starred: true);
      expect(starred.starred, isTrue);
      expect(starred.isPdf, isTrue);
      expect(starred.externalPath, '/docs/notes.pdf');
    });
  });

  group('home file / folder partition', () {
    test('PDFs interleave with scraps by incoming recency order', () {
      final olderScrap = _node(
        id: 's1',
        type: NodeType.note,
        updatedAt: DateTime(2026, 8, 1),
        title: 'Old scrap',
      );
      final newerPdf = _node(
        id: 'p1',
        type: NodeType.document,
        updatedAt: DateTime(2026, 8, 10),
        externalPath: 'file.pdf',
        title: 'New PDF',
      );
      final newestScrap = _node(
        id: 's2',
        type: NodeType.note,
        updatedAt: DateTime(2026, 8, 16),
        title: 'New scrap',
      );
      final pile = _node(
        id: 'f1',
        type: NodeType.folder,
        updatedAt: DateTime(2026, 8, 20),
        title: 'Pile',
      );

      // Recency order as the repository now returns (updated_at DESC).
      final nodes = [pile, newestScrap, newerPdf, olderScrap];
      final files = homeFileNodes(nodes);
      final folders = homeFolderNodes(nodes);

      expect(files.map((n) => n.id), ['s2', 'p1', 's1']);
      expect(folders.map((n) => n.id), ['f1']);
      expect(files.every((n) => n.isFile), isTrue);
    });
  });

  group('canDropOntoFolder', () {
    final pile = _node(id: 'folder', type: NodeType.folder);
    final scrap = _node(id: 'scrap', type: NodeType.note);

    test('allows tucking a scrap or pile into another pile', () {
      expect(canDropOntoFolder(scrap, pile), isTrue);
      expect(
        canDropOntoFolder(
          _node(id: 'other', type: NodeType.folder),
          pile,
        ),
        isTrue,
      );
    });

    test('rejects self, current parent, deleted, and non-folders', () {
      expect(canDropOntoFolder(pile, pile), isFalse);
      expect(
        canDropOntoFolder(
          _node(id: 'child', type: NodeType.note, parentId: pile.id),
          pile,
        ),
        isFalse,
      );
      expect(
        canDropOntoFolder(
          scrap.copyWith(deletedAt: DateTime(2026, 8, 1)),
          pile,
        ),
        isFalse,
      );
      expect(canDropOntoFolder(scrap, scrap), isFalse);
    });
  });

  test('savedFolderId is a distinct sentinel from trash and root', () {
    expect(savedFolderId, 'saved');
    expect(savedFolderId, isNot(trashFolderId));
    expect(savedFolderId, isNot('root'));
  });
}
