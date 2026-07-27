import 'dart:convert';
import 'dart:typed_data';

enum ChatRole { user, assistant }

/// A single message in an AI chat conversation.
class ChatMessage {
  final String id;
  final String conversationId;
  final ChatRole role;
  final String content;
  final List<String> suggestions;
  final String? modelUsed;
  final DateTime createdAt;
  final bool isError;
  /// When true, the message is sent to the model but not shown in the UI
  /// (used for Smelt handoff context).
  final bool hidden;
  /// Optional PNG image attached to the message (e.g. a canvas selection).
  final Uint8List? image;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.suggestions = const [],
    this.modelUsed,
    required this.createdAt,
    this.isError = false,
    this.hidden = false,
    this.image,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role.name,
      'content': content,
      'suggestions': jsonEncode(suggestions),
      'model_used': modelUsed,
      'created_at': createdAt.toIso8601String(),
      'is_error': isError ? 1 : 0,
      'hidden': hidden ? 1 : 0,
      'image': image == null ? null : base64Encode(image!),
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    List<String> suggestions = const [];
    final raw = map['suggestions'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          suggestions = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    Uint8List? image;
    final rawImage = map['image'];
    if (rawImage is String && rawImage.isNotEmpty) {
      try {
        image = base64Decode(rawImage);
      } catch (_) {}
    }

    return ChatMessage(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      role: ChatRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => ChatRole.user,
      ),
      content: map['content'] as String? ?? '',
      suggestions: suggestions,
      modelUsed: map['model_used'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      isError: (map['is_error'] as int? ?? 0) == 1,
      hidden: (map['hidden'] as int? ?? 0) == 1,
      image: image,
    );
  }

  ChatMessage copyWith({
    String? content,
    List<String>? suggestions,
    String? modelUsed,
    bool? isError,
    bool? hidden,
    Uint8List? image,
    bool clearImage = false,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      suggestions: suggestions ?? this.suggestions,
      modelUsed: modelUsed ?? this.modelUsed,
      createdAt: createdAt,
      isError: isError ?? this.isError,
      hidden: hidden ?? this.hidden,
      image: clearImage ? null : (image ?? this.image),
    );
  }
}
