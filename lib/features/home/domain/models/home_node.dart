import 'package:uuid/uuid.dart';

enum NodeType { folder, note, document }

class HomeNode {
  final String id;
  final String parentId;
  final String title;
  final NodeType type;
  final DateTime updatedAt;
  final String? externalPath;

  const HomeNode({
    required this.id,
    required this.parentId,
    required this.title,
    required this.type,
    required this.updatedAt,
    this.externalPath,
  });

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
    };
  }

  factory HomeNode.fromMap(Map<String, dynamic> map) {
    return HomeNode(
      id: map['id'],
      parentId: map['parent_id'],
      title: map['title'],
      type: NodeType.values.firstWhere((e) => e.name == map['type'], orElse: () => NodeType.note),
      updatedAt: DateTime.parse(map['updated_at']),
      externalPath: map['external_path'],
    );
  }

  HomeNode copyWith({
    String? title,
    String? parentId,
    DateTime? updatedAt,
  }) {
    return HomeNode(
      id: id,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      type: type,
      updatedAt: updatedAt ?? this.updatedAt,
      externalPath: externalPath,
    );
  }
}
