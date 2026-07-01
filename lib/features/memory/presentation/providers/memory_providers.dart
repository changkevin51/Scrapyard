import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/memory_repository.dart';
import '../../data/memory_service.dart';
import '../../domain/models/memory_models.dart';

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  return MemoryRepository();
});

final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService(ref.watch(memoryRepositoryProvider));
});

// For settings UI
final autoPatternsProvider = FutureProvider<List<MemoryPattern>>((ref) async {
  final repo = ref.watch(memoryRepositoryProvider);
  final all = await repo.getMemoryPatterns();
  return all.where((p) => p.patternType == PatternType.auto).toList();
});

final userRulesProvider = FutureProvider<List<UserRule>>((ref) async {
  final repo = ref.watch(memoryRepositoryProvider);
  return await repo.getUserRules();
});

final studySessionsProvider = FutureProvider<List<StudySession>>((ref) async {
  final repo = ref.watch(memoryRepositoryProvider);
  return await repo.getStudySessions();
});
