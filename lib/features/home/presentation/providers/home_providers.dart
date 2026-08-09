import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/home_repository.dart';
import '../../domain/models/home_node.dart';
import 'scrap_thumbnail_preloader.dart';

export 'scrap_thumbnail_preloader.dart';

final homeRepositoryProvider = Provider((ref) => HomeRepository());

/// Drop + re-render a single note after the user edits it.
void invalidateNoteThumbnail(WidgetRef ref, String noteId) {
  unawaited(ref.read(scrapThumbnailPreloaderProvider).refreshNote(noteId));
}

// Navigation Path Trackings
final currentFolderIdProvider = StateProvider<String>((ref) => 'root');
final folderPathProvider = StateProvider<List<HomeNode>>((ref) => []);

class HomeNodesNotifier extends StateNotifier<AsyncValue<List<HomeNode>>> {
  final HomeRepository _repository;
  final String _folderId;

  HomeNodesNotifier(this._repository, this._folderId)
      : super(const AsyncValue.loading()) {
    _loadNodes();
  }

  bool get isTrash => _folderId == trashFolderId;

  Future<void> _loadNodes() async {
    try {
      if (isTrash) {
        await _repository.purgeExpiredTrash();
        final nodes = await _repository.getDeletedNodes();
        state = AsyncValue.data(nodes);
      } else {
        // Opportunistic purge while browsing the scrapyard.
        unawaited(_repository.purgeExpiredTrash());
        final nodes = await _repository.getNodes(_folderId);
        state = AsyncValue.data(nodes);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  String get _createParentId => isTrash ? 'root' : _folderId;

  Future<void> createFolder(String title) async {
    final node = HomeNode.create(
      title: title,
      type: NodeType.folder,
      parentId: _createParentId,
    );
    await _repository.insertNode(node);
    await _loadNodes();
  }

  Future<HomeNode> createNote(String title) async {
    final node = HomeNode.create(
      title: title,
      type: NodeType.note,
      parentId: _createParentId,
    );
    await _repository.insertNode(node);
    await _loadNodes();
    return node;
  }

  Future<HomeNode> insertNote(HomeNode node) async {
    await _repository.insertNode(node);
    await _loadNodes();
    return node;
  }

  Future<void> importDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);

      // Copy to app dir so it doesn't get lost from cache
      final appDir = await getApplicationDocumentsDirectory();
      final docPath = '${appDir.path}/${result.files.single.name}';
      await file.copy(docPath);

      final node = HomeNode.create(
        title: result.files.single.name,
        type: NodeType.document,
        parentId: _createParentId,
        externalPath: docPath,
      );
      await _repository.insertNode(node);
      await _loadNodes();
    }
  }

  /// Soft-delete into Recently Deleted (with crush animation upstream).
  Future<void> moveToTrash(String id) async {
    await _repository.softDeleteNode(id);
    await _loadNodes();
  }

  Future<void> restoreFromTrash(String id) async {
    await _repository.restoreNode(id);
    await _loadNodes();
  }

  Future<void> permanentlyDelete(String id) async {
    await _repository.permanentlyDeleteNode(id);
    await _loadNodes();
  }

  Future<void> emptyTrash() async {
    await _repository.emptyTrash();
    await _loadNodes();
  }

  /// Hard delete — prefer [moveToTrash] for user-facing crush.
  Future<void> deleteNode(String id) async {
    await _repository.permanentlyDeleteNode(id);
    await _loadNodes();
  }

  Future<void> renameNode(HomeNode node, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty || trimmed == node.title) return;
    final updated = node.copyWith(title: trimmed, updatedAt: DateTime.now());
    await _repository.updateNode(updated);
    await _loadNodes();
  }

  Future<void> refresh() => _loadNodes();

  /// Persist last-edited times for notes whose canvas content changed.
  Future<void> touchNotes(Iterable<String> ids) async {
    final unique = ids.toSet();
    if (unique.isEmpty) return;
    for (final id in unique) {
      await _repository.touchUpdatedAt(id);
    }
    await _loadNodes();
  }
}

final currentHomeNodesProvider = StateNotifierProvider.autoDispose<
    HomeNodesNotifier, AsyncValue<List<HomeNode>>>((ref) {
  final repo = ref.watch(homeRepositoryProvider);
  final currentFolderId = ref.watch(currentFolderIdProvider);
  return HomeNodesNotifier(repo, currentFolderId);
});
