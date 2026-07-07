import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/smelt_response.dart';
import '../../data/smelt_service.dart';
import 'contextual_engine_provider.dart';

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

  Future<void> smelt({Uint8List? imageBytes}) async {
    try {
      final response = await _smeltService.analyzeSelection(imageBytes);
      state = SmeltState(isLoading: false, response: response);
    } catch (e) {
      state = SmeltState(isLoading: false, error: e.toString());
    }
  }

  Future<void> analyzeSelection(Uint8List imageBytes) async {
    state = const SmeltState(isLoading: true);
    try {
      final response = await _smeltService.analyzeSelection(imageBytes);
      state = SmeltState(isLoading: false, response: response);
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