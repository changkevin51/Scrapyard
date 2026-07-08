import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

final smeltServiceProvider = Provider((ref) {
  return SmeltService(ref.watch(secureStorageProvider));
});

class SmeltState {
  final bool isLoading;
  final SmeltResponse? response;
  final String? error;
  final bool showSteps;

  const SmeltState({
    this.isLoading = false,
    this.response,
    this.error,
    this.showSteps = false,
  });

  SmeltState copyWith({
    bool? isLoading,
    SmeltResponse? response,
    String? error,
    bool clearResponse = false,
    bool clearError = false,
    bool? showSteps,
  }) {
    return SmeltState(
      isLoading: isLoading ?? this.isLoading,
      response: clearResponse ? null : (response ?? this.response),
      error: clearError ? null : (error ?? this.error),
      showSteps: showSteps ?? this.showSteps,
    );
  }
}

class SmeltNotifier extends StateNotifier<SmeltState> {
  final SmeltService _smeltService;

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
      state = const SmeltState(isLoading: true);
      
      final result = await _smeltService.analyzeSelectionStream(
        imageBytes,
        onProgress: ({partialAnswer = '', partialSteps = '', isComplete = false, error}) {
          if (isComplete && partialAnswer != null && partialAnswer.isNotEmpty) {
            final isMath = RegExp(r'[\\{}^_]|frac|sqrt|pm|int|sum|lim|pi|theta').hasMatch(partialAnswer);
            
            final finalResponse = SmeltResponse(
              answer: partialAnswer,
              steps: _cleanSteps(partialSteps ?? ''),
              isMath: isMath,
              modelUsed: 'gemini-3.5-flash',
            );
            state = SmeltState(
              isLoading: false,
              response: finalResponse,
            );
          }
        },
      );

      // If we haven't updated state yet (no streaming progress), set final state
      if (state.isLoading) {
        state = SmeltState(
          isLoading: false,
          response: SmeltResponse(
            answer: result.response.answer,
            steps: _cleanSteps(result.response.steps),
            isMath: result.response.isMath,
            modelUsed: result.response.modelUsed,
          ),
        );
      }
    } catch (e) {
      state = SmeltState(isLoading: false, error: e.toString());
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