import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/home_node.dart';
import '../../data/home_repository.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

final homeRepositoryProvider = Provider((ref) => HomeRepository());

// Navigation Path Trackings
final currentFolderIdProvider = StateProvider<String>((ref) => 'root');
final folderPathProvider = StateProvider<List<HomeNode>>((ref) => []);

class HomeNodesNotifier extends StateNotifier<AsyncValue<List<HomeNode>>> {
  final HomeRepository _repository;
  final String _folderId;
  
  HomeNodesNotifier(this._repository, this._folderId) : super(const AsyncValue.loading()) {
    _loadNodes();
  }
  
  Future<void> _loadNodes() async {
    try {
      final nodes = await _repository.getNodes(_folderId);
      state = AsyncValue.data(nodes);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> createFolder(String title) async {
     final node = HomeNode.create(title: title, type: NodeType.folder, parentId: _folderId);
     await _repository.insertNode(node);
     await _loadNodes();
  }

  Future<void> createNote(String title) async {
     final node = HomeNode.create(title: title, type: NodeType.note, parentId: _folderId);
     await _repository.insertNode(node);
     await _loadNodes();
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
        final docPath = '\${appDir.path}/\${result.files.single.name}';
        await file.copy(docPath);

        final node = HomeNode.create(
           title: result.files.single.name, 
           type: NodeType.document, 
           parentId: _folderId,
           externalPath: docPath,
        );
        await _repository.insertNode(node);
        await _loadNodes();
     }
  }

  Future<void> deleteNode(String id) async {
     await _repository.deleteNode(id);
     await _loadNodes();
  }
}

final currentHomeNodesProvider = StateNotifierProvider.autoDispose<HomeNodesNotifier, AsyncValue<List<HomeNode>>>((ref) {
   final repo = ref.watch(homeRepositoryProvider);
   final currentFolderId = ref.watch(currentFolderIdProvider);
   return HomeNodesNotifier(repo, currentFolderId);
});
