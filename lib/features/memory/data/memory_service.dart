import 'package:uuid/uuid.dart';
import '../domain/models/memory_models.dart';
import 'memory_repository.dart';

class MemoryService {
  final MemoryRepository _repository;
  final Uuid _uuid = const Uuid();
  String? _currentSessionId;

  MemoryService(this._repository) {
    _startSession();
  }

  void _startSession() {
    _currentSessionId = _uuid.v4();
    final session = StudySession(
      id: _currentSessionId!,
      startTime: DateTime.now().millisecondsSinceEpoch,
      documentIds: [],
      totalQueries: 0,
    );
    _repository.saveStudySession(session);
  }

  Future<String> logQuery({
    required String selectedText,
    required String queryMode,
    required String languageDetected,
  }) async {
    final subjectTag = _detectSubjectTag(selectedText);
    final logId = _uuid.v4();
    
    final log = QueryLog(
      id: logId,
      sessionId: _currentSessionId ?? '',
      selectedText: selectedText,
      queryMode: queryMode,
      languageDetected: languageDetected,
      subjectTag: subjectTag,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    
    await _repository.saveQueryLog(log);
    return logId;
  }

  Future<void> recordUsefulness(String logId, bool wasUseful) async {
    await _repository.updateQueryUsefulness(logId, wasUseful);
  }

  Future<MemoryContext> getContextForQuery(String text) async {
    final subjectTag = _detectSubjectTag(text);
    final patterns = await _repository.getMemoryPatterns(subjectTag: subjectTag);
    final rules = await _repository.getUserRules(subjectTag: subjectTag);

    return MemoryContext(
      activePatterns: patterns,
      activeRules: rules.where((r) => r.isActive).toList(),
      primarySubject: subjectTag,
    );
  }

  String _detectSubjectTag(String text) {
     final lower = text.toLowerCase();
     if (lower.contains('kanji') || lower.contains('jlpt') || lower.contains('grammar')) return 'japanese_study';
     if (lower.contains('equation') || lower.contains('theorem') || lower.contains('integral')) return 'math';
     if (lower.contains('anatomy') || lower.contains('cell') || lower.contains('protein')) return 'biology';
     return 'general';
  }
}
