import 'package:uuid/uuid.dart';
import '../domain/models/memory_models.dart';
import 'memory_repository.dart';

class PatternAnalyzer {
  final MemoryRepository _repository;
  final Uuid _uuid = const Uuid();

  PatternAnalyzer(this._repository);

  Future<void> analyzeLast7Days() async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final logs = await _repository.getRecentQueryLogs(sevenDaysAgo);

    if (logs.isEmpty) return;

    // A very simplistic mock of pattern recognition for Phase 8.
    // In a real agent, this would run a clustering algo or pass the logs to an LLM.

    int japaneseLogs = 0;
    int usefulJapaneseExplanations = 0;
    
    for (var log in logs) {
       if (log.subjectTag == 'japanese_study') {
          japaneseLogs++;
          if (log.wasUseful == true && log.queryMode == 'explain') {
             usefulJapaneseExplanations++;
          }
       }
    }

    if (japaneseLogs > 5) {
       double confidence = usefulJapaneseExplanations / japaneseLogs;
       // Clamp confidence below 0.35 for the first week per user prompt.
       if (confidence > 0.35) confidence = 0.35;

       if (confidence > 0.1) {
          final pattern = MemoryPattern(
             id: _uuid.v4(),
             patternType: PatternType.auto,
             subjectTag: 'japanese_study',
             ruleJson: 'User strongly prefers deep contextual explanations over direct definitions.',
             confidence: confidence,
             createdAt: now.millisecondsSinceEpoch,
             lastAppliedAt: now.millisecondsSinceEpoch,
          );
          await _repository.saveMemoryPattern(pattern);
       }
    }
  }
}

// Global top-level function for flutter_workmanager
@pragma('vm:entry-point')
void memoryPatternTask() {
   // Workmanager().executeTask((taskName, inputData) async {
   //    final repo = MemoryRepository();
   //    final analyzer = PatternAnalyzer(repo);
   //    await analyzer.analyzeLast7Days();
   //    return true;
   // });
}
