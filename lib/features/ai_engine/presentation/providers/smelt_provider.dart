import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import '../../data/api_key_service.dart';
import '../../_debug_log_helper.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

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

  ApiKeyNotifier(this._service) : super(const AsyncValue.loading()) {
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
    state = AsyncValue.data(await _service.read());
  }

  Future<void> clear() async {
    await _service.clear();
    state = const AsyncValue.data(null);
  }

  Future<ApiKeyTestResult> test(String key) {
    return _service.test(key);
  }
}

final apiKeyProvider =
    StateNotifierProvider<ApiKeyNotifier, AsyncValue<String?>>((ref) {
  return ApiKeyNotifier(ref.watch(apiKeyServiceProvider));
});

class SmeltState {
  final bool isLoading;
  final SmeltResponse? response;
  final String? error;
  final bool showSteps;
  /// Last canvas capture used for smelt (for chat handoff).
  final Uint8List? lastImageBytes;

  const SmeltState({
    this.isLoading = false,
    this.response,
    this.error,
    this.showSteps = false,
    this.lastImageBytes,
  });

  SmeltState copyWith({
    bool? isLoading,
    SmeltResponse? response,
    String? error,
    bool clearResponse = false,
    bool clearError = false,
    bool? showSteps,
    Uint8List? lastImageBytes,
  }) {
    return SmeltState(
      isLoading: isLoading ?? this.isLoading,
      response: clearResponse ? null : (response ?? this.response),
      error: clearError ? null : (error ?? this.error),
      showSteps: showSteps ?? this.showSteps,
      lastImageBytes: lastImageBytes ?? this.lastImageBytes,
    );
  }
}

class SmeltNotifier extends StateNotifier<SmeltState> {
  final SmeltService _smeltService;
  int _onProgressCallCount = 0;

  SmeltNotifier(this._smeltService) : super(const SmeltState());

  void startLoading() {
    state = const SmeltState(isLoading: true);
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

  /// Streaming smelt that shows results as soon as they arrive
  Future<void> smelt({Uint8List? imageBytes}) async {
    try {
      state = SmeltState(isLoading: true, lastImageBytes: imageBytes);

      final result = await _smeltService.analyzeSelectionStream(
        imageBytes,
        onProgress: ({
          partialAnswer = '',
          partialSteps = '',
          partialSuggestions,
          isComplete = false,
          error,
        }) {
          _onProgressCallCount++;
          // #region agent log
          dlog(
              'H5_H2_onProgress_call',
              'onProgress invoked - checking call count and raw partialSteps vs cleaned',
              {
                'callCount': _onProgressCallCount,
                'isComplete': isComplete,
                'partialStepsJsonEncoded': jsonEncode(partialSteps ?? ''),
                'cleanedStepsJsonEncoded':
                    jsonEncode(_cleanSteps(partialSteps ?? '')),
              });
          // #endregion
        },
      );

      state = SmeltState(
        isLoading: false,
        lastImageBytes: imageBytes,
        response: SmeltResponse(
          answer: result.response.answer,
          steps: _cleanSteps(result.response.steps),
          isMath: result.response.isMath,
          modelUsed: result.response.modelUsed,
          suggestions: result.response.suggestions,
        ),
      );
    } catch (e) {
      state = SmeltState(
        isLoading: false,
        error: e.toString(),
        lastImageBytes: imageBytes,
      );
    }
  }

  void toggleSteps() {
    state = state.copyWith(showSteps: !state.showSteps);
  }

  void clearState() {
    state = const SmeltState();
  }
}

final smeltProvider = StateNotifierProvider<SmeltNotifier, SmeltState>((ref) {
  return SmeltNotifier(ref.watch(smeltServiceProvider));
});
