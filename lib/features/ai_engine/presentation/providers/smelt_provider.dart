import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import '../../data/api_key_service.dart';
import '../../data/gemini_api.dart';
import '../../../ai_chat/domain/models/gemini_model.dart';
import '../../smelt_timing.dart';

final secureStorageProvider = Provider((ref) => GeminiApi.secureStorage());

final smeltServiceProvider = Provider((ref) {
  return SmeltService(ref.watch(secureStorageProvider));
});

final apiKeyServiceProvider = Provider((ref) {
  return ApiKeyService(ref.watch(secureStorageProvider));
});

/// True after we've auto-prompted for an API key this session.
final apiKeySetupPromptedProvider = StateProvider<bool>((ref) => false);

class ApiKeyNotifier extends StateNotifier<AsyncValue<String?>> {
  final ApiKeyService _service;
  final SmeltService _smeltService;

  ApiKeyNotifier(this._service, this._smeltService)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    state = const AsyncValue.loading();
    try {
      final key = await _service.read();
      state = AsyncValue.data(key);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> save(String key) async {
    await _service.save(key);
    _smeltService.invalidateApiKeyCache();
    state = AsyncValue.data(await _service.read());
  }

  Future<void> clear() async {
    await _service.clear();
    _smeltService.invalidateApiKeyCache();
    state = const AsyncValue.data(null);
  }

  Future<ApiKeyTestResult> test(String key) {
    return _service.test(key);
  }
}

final apiKeyProvider =
    StateNotifierProvider<ApiKeyNotifier, AsyncValue<String?>>((ref) {
  return ApiKeyNotifier(
    ref.watch(apiKeyServiceProvider),
    ref.watch(smeltServiceProvider),
  );
});

/// Cached Smelt result for one expression within the current app session.
class SmeltCacheEntry {
  final SmeltResponse response;
  final Uint8List? imageBytes;

  const SmeltCacheEntry({
    required this.response,
    this.imageBytes,
  });
}

class SmeltState {
  final bool isLoading;
  final SmeltResponse? response;
  final String? error;
  final bool showSteps;
  final bool showCodeOutput;
  /// Last canvas capture used for smelt (for chat handoff).
  final Uint8List? lastImageBytes;
  /// Session-cache key for the active popup (note + stroke set).
  final String? cacheKey;
  /// Whether this request prompted the model to verify via code execution.
  final bool forceCodeExecution;

  const SmeltState({
    this.isLoading = false,
    this.response,
    this.error,
    this.showSteps = false,
    this.showCodeOutput = false,
    this.lastImageBytes,
    this.cacheKey,
    this.forceCodeExecution = false,
  });

  SmeltState copyWith({
    bool? isLoading,
    SmeltResponse? response,
    String? error,
    bool clearResponse = false,
    bool clearError = false,
    bool? showSteps,
    bool? showCodeOutput,
    Uint8List? lastImageBytes,
    String? cacheKey,
    bool clearCacheKey = false,
    bool? forceCodeExecution,
  }) {
    return SmeltState(
      isLoading: isLoading ?? this.isLoading,
      response: clearResponse ? null : (response ?? this.response),
      error: clearError ? null : (error ?? this.error),
      showSteps: showSteps ?? this.showSteps,
      showCodeOutput: showCodeOutput ?? this.showCodeOutput,
      lastImageBytes: lastImageBytes ?? this.lastImageBytes,
      cacheKey: clearCacheKey ? null : (cacheKey ?? this.cacheKey),
      forceCodeExecution: forceCodeExecution ?? this.forceCodeExecution,
    );
  }
}

class SmeltNotifier extends StateNotifier<SmeltState> {
  final SmeltService _smeltService;

  /// In-memory cache for this app session (survives popup dismiss).
  final Map<String, SmeltCacheEntry> _sessionCache = {};

  SmeltNotifier(this._smeltService) : super(const SmeltState());

  /// Stable cache key for a note + selected stroke / text set.
  static String cacheKeyFor({
    required String noteId,
    required Iterable<String> strokeIds,
    Iterable<String> textIds = const [],
  }) {
    final strokes = strokeIds.toList()..sort();
    final texts = textIds.toList()..sort();
    if (texts.isEmpty) return '$noteId:${strokes.join('|')}';
    return '$noteId:s=${strokes.join('|')};t=${texts.join('|')}';
  }

  bool hasCached(String key) => _sessionCache.containsKey(key);

  /// Overlap secure-storage key read with canvas/PDF capture.
  Future<void> prefetchApiKey() => _smeltService.prefetchApiKey();

  /// Restore a previously saved response into the popup state (no API call).
  bool restoreCached(String key) {
    final entry = _sessionCache[key];
    if (entry == null) return false;
    final response = entry.response;
    state = SmeltState(
      response: response,
      lastImageBytes: entry.imageBytes,
      cacheKey: key,
      // Process-style answers (empty answer box) should show steps by default.
      showSteps: !response.hasDirectAnswer && response.steps.trim().isNotEmpty,
    );
    return true;
  }

  void startLoading({String? cacheKey, bool forceCodeExecution = false}) {
    state = SmeltState(
      isLoading: true,
      cacheKey: cacheKey ?? state.cacheKey,
      lastImageBytes: state.lastImageBytes,
      forceCodeExecution: forceCodeExecution,
    );
  }

  /// Remove duplicate steps from AI output
  /// Handles both numbered (1., 2., etc.) and bullet-point format
  static String _cleanSteps(String steps) {
    if (steps.isEmpty) return steps;

    final lines = steps.split('\n');
    final result = <String>[];
    final seenLines = <String>{};
    final seenStepNumbers = <String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        result.add(line);
        continue;
      }

      // Skip exact duplicate lines
      if (!seenLines.add(trimmed)) continue;

      // For numbered steps, skip if step number already appeared
      final stepMatch = RegExp(r'^(\d+)\.\s*').firstMatch(trimmed);
      if (stepMatch != null && !seenStepNumbers.add(stepMatch.group(1)!)) {
        continue;
      }

      result.add(line);
    }

    return result.join('\n');
  }

  /// Streaming smelt that shows results as soon as they arrive.
  /// On success, stores the result under [cacheKey] for this session.
  Future<void> smelt({
    Uint8List? imageBytes,
    String? selectedText,
    String? cacheKey,
    String? preferredModel,
    bool singleModel = false,
    bool forceCodeExecution = false,
  }) async {
    final key = cacheKey ?? state.cacheKey;
    SmeltTiming.step('provider_smelt_start', extra: {
      'hasImage': imageBytes != null,
      'imageBytes': imageBytes?.length ?? 0,
      'hasTypedText': selectedText != null && selectedText.trim().isNotEmpty,
      'singleModel': singleModel,
      'forceCodeExecution': forceCodeExecution,
      'preferredModel': preferredModel ?? 'default',
    });
    try {
      if (singleModel && key != null) {
        _sessionCache.remove(key);
      }

      state = SmeltState(
        isLoading: true,
        lastImageBytes: imageBytes,
        cacheKey: key,
        forceCodeExecution: forceCodeExecution,
      );
      SmeltTiming.step('provider_loading_state_set');

      final result = await _smeltService.analyzeSelectionStream(
        imageBytes,
        selectedText: selectedText,
        preferredModel: preferredModel,
        singleModel: singleModel,
        forceCodeExecution: forceCodeExecution,
      );
      SmeltTiming.step('provider_api_returned', extra: {
        'modelUsed': result.modelUsed,
        'didFallback': result.didFallback,
        'codeRuns': result.response.codeRuns.length,
      });

      final fallbackNote = result.didFallback
          ? GeminiChatModel.fallbackMessage(
              requestedModelId: result.requestedModel!,
              usedModelId: result.modelUsed,
              reason: result.fallbackReason!,
            )
          : null;

      final response = SmeltResponse(
        answer: result.response.answer,
        steps: _cleanSteps(result.response.steps),
        isMath: result.response.isMath,
        modelUsed: result.modelUsed,
        modelFallbackNote: fallbackNote,
        suggestions: result.response.suggestions,
        codeRuns: result.response.codeRuns,
      );

      if (key != null) {
        _sessionCache[key] = SmeltCacheEntry(
          response: response,
          imageBytes: imageBytes,
        );
      }

      // No punchline answer (e.g. proofs) — show steps immediately.
      final autoShowSteps =
          !response.hasDirectAnswer && response.steps.trim().isNotEmpty;

      state = SmeltState(
        isLoading: false,
        lastImageBytes: imageBytes,
        response: response,
        cacheKey: key,
        forceCodeExecution: forceCodeExecution,
        showSteps: autoShowSteps,
      );
      SmeltTiming.step('provider_result_state_set', extra: {
        'autoShowSteps': autoShowSteps,
        'answerChars': response.answer.length,
        'stepsChars': response.steps.length,
      });
    } catch (e) {
      SmeltTiming.step('provider_error');
      state = SmeltState(
        isLoading: false,
        error: GeminiApi.userFacingError(e),
        lastImageBytes: imageBytes,
        cacheKey: key,
        forceCodeExecution: forceCodeExecution,
      );
    }
  }

  /// Re-run Smelt with the last captured image (updates session cache).
  Future<void> retry({
    Uint8List? imageBytes,
    String? preferredModel,
    bool singleModel = false,
    bool forceCodeExecution = false,
  }) async {
    await smelt(
      imageBytes: imageBytes ?? state.lastImageBytes,
      cacheKey: state.cacheKey,
      preferredModel: preferredModel,
      singleModel: singleModel,
      forceCodeExecution: forceCodeExecution,
    );
  }

  void toggleSteps() {
    state = state.copyWith(showSteps: !state.showSteps);
  }

  void toggleCodeOutput() {
    state = state.copyWith(showCodeOutput: !state.showCodeOutput);
  }

  /// Clears the open popup UI state. Session cache is kept.
  void clearState() {
    state = const SmeltState();
  }
}

final smeltProvider = StateNotifierProvider<SmeltNotifier, SmeltState>((ref) {
  return SmeltNotifier(ref.watch(smeltServiceProvider));
});
