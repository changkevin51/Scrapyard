import 'package:uuid/uuid.dart';

enum NodeType { folder, note, document }

/// Sentinel [currentFolderIdProvider] value for the Recently Deleted view.
const String trashFolderId = 'trash';

/// How long crushed items stay in Recently Deleted before permanent purge.
const Duration trashRetention = Duration(days: 30);

class HomeNode {
  final String id;
  final String parentId;
  final String title;
  final NodeType type;
  final DateTime updatedAt;
  final String? externalPath;
  final DateTime? deletedAt;

  const HomeNode({
    required this.id,
    required this.parentId,
    required this.title,
    required this.type,
    required this.updatedAt,
    this.externalPath,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  /// Whole days remaining before permanent purge; null if not deleted.
  int? get trashDaysRemaining {
    final deleted = deletedAt;
    if (deleted == null) return null;
    final elapsed = DateTime.now().difference(deleted).inDays;
    return (trashRetention.inDays - elapsed).clamp(0, trashRetention.inDays);
  }

  factory HomeNode.create({
    required String title,
    required NodeType type,
    String parentId = 'root',
    String? externalPath,
  }) {
    return HomeNode(
      id: const Uuid().v4(),
      parentId: parentId,
      title: title,
      type: type,
      updatedAt: DateTime.now(),
      externalPath: externalPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'parent_id': parentId,
      'title': title,
      'type': type.name,
      'updated_at': updatedAt.toIso8601String(),
      'external_path': externalPath,
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory HomeNode.fromMap(Map<String, dynamic> map) {
    final deletedRaw = map['deleted_at'] as String?;
    return HomeNode(
      id: map['id'],
      parentId: map['parent_id'],
      title: map['title'],
      type: NodeType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => NodeType.note,
      ),
      updatedAt: DateTime.parse(map['updated_at']),
      externalPath: map['external_path'],
      deletedAt: deletedRaw != null && deletedRaw.isNotEmpty
          ? DateTime.tryParse(deletedRaw)
          : null,
    );
  }

  HomeNode copyWith({
    String? title,
    String? parentId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return HomeNode(
      id: id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      type: type,
      updatedAt: updatedAt ?? this.updatedAt,
      externalPath: externalPath,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }
}
