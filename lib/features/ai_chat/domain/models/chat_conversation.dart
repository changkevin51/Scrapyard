/// A chat conversation thread (global history, optionally linked to a note).
class ChatConversation {
  final String id;
  final String title;
  final String? noteId;
  final String? noteTitle;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatConversation({
    required this.id,
    required this.title,
    this.noteId,
    this.noteTitle,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'note_id': noteId,
      'note_title': noteTitle,
      'model': model,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ChatConversation.fromMap(Map<String, dynamic> map) {
    return ChatConversation(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Chat',
      noteId: map['note_id'] as String?,
      noteTitle: map['note_title'] as String?,
      model: map['model'] as String? ?? 'gemini-3.5-flash-lite',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  ChatConversation copyWith({
    String? title,
    String? model,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id,
      title: title ?? this.title,
      noteId: noteId,
      noteTitle: noteTitle,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Truncate first user message into a short title.
  static String titleFromMessage(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'New chat';
    if (cleaned.length <= 40) return cleaned;
    return '${cleaned.substring(0, 37)}…';
  }
}
