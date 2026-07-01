import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/contextual_query.dart';
import '../../domain/models/contextual_response.dart';
import '../../data/ai_engine_service.dart';
import '../../../memory/data/memory_service.dart';
import '../../../memory/presentation/providers/memory_providers.dart';
import '../../../language_layer/domain/services/language_detector.dart';

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

final aiEngineServiceProvider = Provider((ref) {
  return AIEngineService(ref.watch(secureStorageProvider));
});

class ContextualEngineState {
  final bool isLoading;
  final ContextualResponse? response;
  final String? error;
  final String? currentLogId;

  ContextualEngineState({
    this.isLoading = false,
    this.response,
    this.error,
    this.currentLogId,
  });

  ContextualEngineState copyWith({
    bool? isLoading,
    ContextualResponse? response,
    String? error,
    bool clearResponse = false,
    bool clearError = false,
    String? currentLogId,
    bool clearLogId = false,
  }) {
    return ContextualEngineState(
      isLoading: isLoading ?? this.isLoading,
      response: clearResponse ? null : (response ?? this.response),
      error: clearError ? null : (error ?? this.error),
      currentLogId: clearLogId ? null : (currentLogId ?? this.currentLogId),
    );
  }
}

class ContextualEngineNotifier extends StateNotifier<ContextualEngineState> {
  final AIEngineService _aiEngineService;
  final MemoryService _memoryService;

  ContextualEngineNotifier(this._aiEngineService, this._memoryService) : super(ContextualEngineState());

  Future<void> triggerQuery(ContextualQuery query) async {
    state = state.copyWith(isLoading: true, clearError: true, clearResponse: true, clearLogId: true);
    try {
      final detectedLang = LanguageDetector.detect(query.selectedText);
      
      final logId = await _memoryService.logQuery(
        selectedText: query.selectedText,
        queryMode: query.queryMode.name,
        languageDetected: detectedLang.name,
      );

      final memContext = await _memoryService.getContextForQuery(query.selectedText);
      final queryWithMem = ContextualQuery(
         selectedText: query.selectedText,
         surroundingContext: query.surroundingContext,
         languageHint: query.languageHint,
         queryMode: query.queryMode,
         memoryContext: memContext,
      );

      final response = await _aiEngineService.query(queryWithMem);
      state = state.copyWith(isLoading: false, response: response, currentLogId: logId);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void clearState() {
    state = ContextualEngineState();
  }
}

final contextualEngineProvider = StateNotifierProvider<ContextualEngineNotifier, ContextualEngineState>((ref) {
  return ContextualEngineNotifier(ref.watch(aiEngineServiceProvider), ref.watch(memoryServiceProvider));
});
