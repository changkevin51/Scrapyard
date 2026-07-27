import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../ai_engine/presentation/providers/smelt_provider.dart'
    show secureStorageProvider;
import '../../data/chat_repository.dart';
import '../../data/gemini_chat_service.dart';
import '../../domain/models/chat_conversation.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/gemini_model.dart';

const _uuid = Uuid();

// ── Seed from Smelt handoff ──────────────────────────────────────

class ChatSeed {
  final String smeltAnswer;
  final String smeltSteps;
  final Uint8List? image;
  final String? autoSend;
  final String? noteId;
  final String? noteTitle;

  const ChatSeed({
    required this.smeltAnswer,
    this.smeltSteps = '',
    this.image,
    this.autoSend,
    this.noteId,
    this.noteTitle,
  });
}

final pendingChatSeedProvider = StateProvider<ChatSeed?>((ref) => null);

// ── Repository / service ─────────────────────────────────────────

final chatRepositoryProvider = Provider((ref) => ChatRepository());

final geminiChatServiceProvider = Provider((ref) {
  return GeminiChatService(ref.watch(secureStorageProvider));
});

// Re-export for convenience if secure storage isn't already watched
final chatSecureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return ref.watch(secureStorageProvider);
});

// ── Panel UI state ───────────────────────────────────────────────

final chatPanelOpenProvider = StateProvider<bool>((ref) => false);

final chatPanelWidthProvider =
    StateNotifierProvider<ChatPanelWidthNotifier, double>((ref) {
  return ChatPanelWidthNotifier();
});

class ChatPanelWidthNotifier extends StateNotifier<double> {
  static const _prefsKey = 'ai_chat_panel_width';
  static const defaultWidth = 360.0;

  ChatPanelWidthNotifier() : super(defaultWidth) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getDouble(_prefsKey) ?? defaultWidth;
  }

  Future<void> setWidth(double width) async {
    state = width.clamp(280.0, 560.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, state);
  }
}

// ── Model preference ─────────────────────────────────────────────

final chatModelProvider =
    StateNotifierProvider<ChatModelNotifier, String>((ref) {
  return ChatModelNotifier();
});

class ChatModelNotifier extends StateNotifier<String> {
  static const _prefsKey = 'ai_chat_model';

  ChatModelNotifier() : super(GeminiChatModel.defaultModel.id) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && GeminiChatModel.byId(saved) != null) {
      state = saved;
    }
  }

  Future<void> setModel(String modelId) async {
    if (GeminiChatModel.byId(modelId) == null) return;
    state = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, modelId);
  }
}

// ── Conversations list ───────────────────────────────────────────

final conversationsProvider = StateNotifierProvider<ConversationsNotifier,
    AsyncValue<List<ChatConversation>>>((ref) {
  return ConversationsNotifier(ref.watch(chatRepositoryProvider));
});

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<ChatConversation>>> {
  final ChatRepository _repo;

  ConversationsNotifier(this._repo) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final list = await _repo.listConversations();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> delete(String id) async {
    await _repo.deleteConversation(id);
    await refresh();
  }

  Future<void> deleteAll() async {
    await _repo.deleteAll();
    state = const AsyncValue.data([]);
  }
}

// ── Active chat ──────────────────────────────────────────────────

class ChatState {
  final ChatConversation? conversation;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String streamingText;
  final String? error;

  const ChatState({
    this.conversation,
    this.messages = const [],
    this.isStreaming = false,
    this.streamingText = '',
    this.error,
  });

  List<ChatMessage> get visibleMessages =>
      messages.where((m) => !m.hidden).toList();

  ChatState copyWith({
    ChatConversation? conversation,
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? streamingText,
    String? error,
    bool clearConversation = false,
    bool clearError = false,
  }) {
    return ChatState(
      conversation:
          clearConversation ? null : (conversation ?? this.conversation),
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingText: streamingText ?? this.streamingText,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repo;
  final GeminiChatService _service;
  final Ref _ref;
  StreamSubscription<String>? _sub;
  String? _streamingAssistantId;

  ChatNotifier(this._repo, this._service, this._ref)
      : super(const ChatState());

  void newChat({String? noteId, String? noteTitle}) {
    _cancelStream();
    state = const ChatState(
      conversation: null,
      messages: [],
      // stash note context on a placeholder via a transient field —
      // we create the real conversation on first send.
    );
    _pendingNoteId = noteId;
    _pendingNoteTitle = noteTitle;
  }

  String? _pendingNoteId;
  String? _pendingNoteTitle;
  Uint8List? _pendingImage;

  Future<void> openConversation(String id) async {
    _cancelStream();
    final conv = await _repo.getConversation(id);
    if (conv == null) return;
    final messages = await _repo.loadMessages(id);
    _pendingNoteId = conv.noteId;
    _pendingNoteTitle = conv.noteTitle;
    _pendingImage = null;
    state = ChatState(conversation: conv, messages: messages);
  }

  Future<void> consumeSeed(ChatSeed seed) async {
    _cancelStream();
    final modelId = _ref.read(chatModelProvider);
    final now = DateTime.now();
    final convId = _uuid.v4();

    final title = ChatConversation.titleFromMessage(
      seed.autoSend ?? 'Smelt follow-up',
    );

    final conv = ChatConversation(
      id: convId,
      title: title,
      noteId: seed.noteId,
      noteTitle: seed.noteTitle,
      model: modelId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.upsertConversation(conv);

    final contextParts = <String>[
      'The user just used Smelt (handwriting analysis) on their notes.',
      if (seed.smeltAnswer.isNotEmpty) 'Smelt answer:\n${seed.smeltAnswer}',
      if (seed.smeltSteps.isNotEmpty) 'Steps:\n${seed.smeltSteps}',
      'Continue helping them with follow-up questions about this content.',
    ];

    final hiddenUser = ChatMessage(
      id: _uuid.v4(),
      conversationId: convId,
      role: ChatRole.user,
      content: contextParts.join('\n\n'),
      createdAt: now,
      hidden: true,
    );
    await _repo.insertMessage(hiddenUser);

    final visibleAssistant = ChatMessage(
      id: _uuid.v4(),
      conversationId: convId,
      role: ChatRole.assistant,
      content: [
        seed.smeltAnswer,
        if (seed.smeltSteps.isNotEmpty) '\n\n${seed.smeltSteps}',
      ].join(),
      createdAt: now.add(const Duration(milliseconds: 1)),
      modelUsed: modelId,
    );
    await _repo.insertMessage(visibleAssistant);

    _pendingNoteId = seed.noteId;
    _pendingNoteTitle = seed.noteTitle;
    _pendingImage = seed.image;

    state = ChatState(
      conversation: conv,
      messages: [hiddenUser, visibleAssistant],
    );
    await _ref.read(conversationsProvider.notifier).refresh();

    if (seed.autoSend != null && seed.autoSend!.trim().isNotEmpty) {
      await send(seed.autoSend!.trim());
    }
  }

  Future<void> send(String text, {Uint8List? imageBytes}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isStreaming) return;

    final modelId = _ref.read(chatModelProvider);
    final now = DateTime.now();
    var conv = state.conversation;

    if (conv == null) {
      conv = ChatConversation(
        id: _uuid.v4(),
        title: ChatConversation.titleFromMessage(trimmed),
        noteId: _pendingNoteId,
        noteTitle: _pendingNoteTitle,
        model: modelId,
        createdAt: now,
        updatedAt: now,
      );
      await _repo.upsertConversation(conv);
    } else {
      // Update title if this is effectively the first visible user message
      final hasVisibleUser =
          state.messages.any((m) => m.role == ChatRole.user && !m.hidden);
      if (!hasVisibleUser) {
        conv = conv.copyWith(
          title: ChatConversation.titleFromMessage(trimmed),
          updatedAt: now,
        );
      } else {
        conv = conv.copyWith(updatedAt: now, model: modelId);
      }
      await _repo.upsertConversation(conv);
    }

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      conversationId: conv.id,
      role: ChatRole.user,
      content: trimmed,
      createdAt: now,
    );
    await _repo.insertMessage(userMsg);

    final assistantId = _uuid.v4();
    _streamingAssistantId = assistantId;

    final historyForApi = [...state.messages, userMsg];
    final image = imageBytes ?? _pendingImage;
    _pendingImage = null; // only attach once

    state = state.copyWith(
      conversation: conv,
      messages: [...state.messages, userMsg],
      isStreaming: true,
      streamingText: '',
      clearError: true,
    );
    await _ref.read(conversationsProvider.notifier).refresh();

    ChatStreamResult? result;
    final buffer = StringBuffer();

    try {
      final stream = _service.streamChat(
        history: historyForApi,
        preferredModel: modelId,
        imageBytes: image,
        onComplete: (r) => result = r,
      );

      _sub = stream.listen(
        (delta) {
          buffer.write(delta);
          if (!mounted) return;
          state = state.copyWith(
            isStreaming: true,
            streamingText: buffer.toString(),
          );
        },
        onError: (e) async {
          await _finalizeError(assistantId, conv!, e.toString());
        },
        onDone: () async {
          final r = result;
          final text = r?.text ?? buffer.toString();
          final suggestions = r?.suggestions ?? const <String>[];
          final usedModel = r?.modelUsed ?? modelId;

          final assistantMsg = ChatMessage(
            id: assistantId,
            conversationId: conv!.id,
            role: ChatRole.assistant,
            content: text,
            suggestions: suggestions,
            modelUsed: usedModel,
            createdAt: DateTime.now(),
          );
          await _repo.insertMessage(assistantMsg);

          final updated = conv.copyWith(updatedAt: DateTime.now());
          await _repo.upsertConversation(updated);

          if (!mounted) return;
          state = ChatState(
            conversation: updated,
            messages: [...state.messages, assistantMsg],
            isStreaming: false,
            streamingText: '',
          );
          _streamingAssistantId = null;
          _sub = null;
          await _ref.read(conversationsProvider.notifier).refresh();
        },
        cancelOnError: true,
      );
    } catch (e) {
      await _finalizeError(assistantId, conv, e.toString());
    }
  }

  Future<void> _finalizeError(
    String assistantId,
    ChatConversation conv,
    String error,
  ) async {
    final assistantMsg = ChatMessage(
      id: assistantId,
      conversationId: conv.id,
      role: ChatRole.assistant,
      content: 'Something went wrong: $error',
      createdAt: DateTime.now(),
      isError: true,
    );
    await _repo.insertMessage(assistantMsg);
    if (!mounted) return;
    state = ChatState(
      conversation: conv,
      messages: [...state.messages, assistantMsg],
      isStreaming: false,
      streamingText: '',
      error: error,
    );
    _streamingAssistantId = null;
    _sub = null;
  }

  void stop() {
    _cancelStream();
    final text = state.streamingText;
    final conv = state.conversation;
    final assistantId = _streamingAssistantId;
    if (conv != null && assistantId != null && text.isNotEmpty) {
      final assistantMsg = ChatMessage(
        id: assistantId,
        conversationId: conv.id,
        role: ChatRole.assistant,
        content: text,
        createdAt: DateTime.now(),
        modelUsed: _ref.read(chatModelProvider),
      );
      _repo.insertMessage(assistantMsg);
      state = ChatState(
        conversation: conv,
        messages: [...state.messages, assistantMsg],
        isStreaming: false,
        streamingText: '',
      );
    } else {
      state = state.copyWith(isStreaming: false, streamingText: '');
    }
    _streamingAssistantId = null;
  }

  Future<void> retry() async {
    final msgs = state.messages;
    if (msgs.isEmpty || state.isStreaming) return;
    // Find last user message and resend
    ChatMessage? lastUser;
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == ChatRole.user && !msgs[i].hidden) {
        lastUser = msgs[i];
        break;
      }
    }
    if (lastUser == null) return;

    // Drop trailing error assistant message if present
    var trimmed = List<ChatMessage>.from(msgs);
    if (trimmed.last.role == ChatRole.assistant && trimmed.last.isError) {
      trimmed = trimmed.sublist(0, trimmed.length - 1);
      state = state.copyWith(messages: trimmed);
    }
    await send(lastUser.content);
  }

  void clear() {
    _cancelStream();
    state = const ChatState();
    _pendingNoteId = null;
    _pendingNoteTitle = null;
    _pendingImage = null;
  }

  void _cancelStream() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _cancelStream();
    super.dispose();
  }
}

final activeChatProvider =
    StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(
    ref.watch(chatRepositoryProvider),
    ref.watch(geminiChatServiceProvider),
    ref,
  );
});
