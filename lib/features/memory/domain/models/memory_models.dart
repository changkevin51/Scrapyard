import 'dart:convert';

enum PatternType { auto, manual }

class StudySession {
  final String id;
  final int startTime;
  final int? endTime;
  final List<String> documentIds;
  final int totalQueries;

  const StudySession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.documentIds,
    required this.totalQueries,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_time': startTime,
      'end_time': endTime,
      'document_ids': jsonEncode(documentIds),
      'total_queries': totalQueries,
    };
  }

  factory StudySession.fromMap(Map<String, dynamic> map) {
    return StudySession(
      id: map['id'],
      startTime: map['start_time'],
      endTime: map['end_time'],
      documentIds: List<String>.from(jsonDecode(map['document_ids'] ?? '[]')),
      totalQueries: map['total_queries'],
    );
  }
}

class QueryLog {
  final String id;
  final String sessionId;
  final String selectedText;
  final String queryMode;
  final String languageDetected;
  final String subjectTag;
  final int timestamp;
  final bool? wasUseful;

  const QueryLog({
    required this.id,
    required this.sessionId,
    required this.selectedText,
    required this.queryMode,
    required this.languageDetected,
    required this.subjectTag,
    required this.timestamp,
    this.wasUseful,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'selected_text': selectedText,
      'query_mode': queryMode,
      'language_detected': languageDetected,
      'subject_tag': subjectTag,
      'timestamp': timestamp,
      'was_useful': wasUseful == null ? null : (wasUseful! ? 1 : 0),
    };
  }

  factory QueryLog.fromMap(Map<String, dynamic> map) {
    return QueryLog(
      id: map['id'],
      sessionId: map['session_id'],
      selectedText: map['selected_text'],
      queryMode: map['query_mode'],
      languageDetected: map['language_detected'],
      subjectTag: map['subject_tag'],
      timestamp: map['timestamp'],
      wasUseful: map['was_useful'] == null ? null : (map['was_useful'] == 1),
    );
  }
}

class MemoryPattern {
  final String id;
  final PatternType patternType;
  final String subjectTag;
  final String ruleJson;
  final double confidence;
  final int createdAt;
  final int lastAppliedAt;

  const MemoryPattern({
    required this.id,
    required this.patternType,
    required this.subjectTag,
    required this.ruleJson,
    required this.confidence,
    required this.createdAt,
    required this.lastAppliedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pattern_type': patternType.name,
      'subject_tag': subjectTag,
      'rule_json': ruleJson,
      'confidence': confidence,
      'created_at': createdAt,
      'last_applied_at': lastAppliedAt,
    };
  }

  factory MemoryPattern.fromMap(Map<String, dynamic> map) {
    return MemoryPattern(
      id: map['id'],
      patternType: PatternType.values.firstWhere((e) => e.name == map['pattern_type'], orElse: () => PatternType.auto),
      subjectTag: map['subject_tag'],
      ruleJson: map['rule_json'],
      confidence: map['confidence'].toDouble(),
      createdAt: map['created_at'],
      lastAppliedAt: map['last_applied_at'],
    );
  }
}

class UserRule {
  final String id;
  final String label;
  final String subjectTag;
  final String instructionText;
  final bool isActive;
  final int priority;

  const UserRule({
    required this.id,
    required this.label,
    required this.subjectTag,
    required this.instructionText,
    required this.isActive,
    required this.priority,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'subject_tag': subjectTag,
      'instruction_text': instructionText,
      'is_active': isActive ? 1 : 0,
      'priority': priority,
    };
  }

  factory UserRule.fromMap(Map<String, dynamic> map) {
    return UserRule(
      id: map['id'],
      label: map['label'],
      subjectTag: map['subject_tag'],
      instructionText: map['instruction_text'],
      isActive: map['is_active'] == 1,
      priority: map['priority'],
    );
  }
}

class MemoryContext {
  final List<MemoryPattern> activePatterns;
  final List<UserRule> activeRules;
  final String primarySubject;

  const MemoryContext({
    required this.activePatterns,
    required this.activeRules,
    required this.primarySubject,
  });

  String toPromptAddition() {
    if (activePatterns.isEmpty && activeRules.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('--- USER PREFERENCES & MEMORY RULES ---');
    if (primarySubject.isNotEmpty) {
      buffer.writeln('Primary Subject Context: $primarySubject');
    }
    
    // Manual rules override
    if (activeRules.isNotEmpty) {
      buffer.writeln('Strict User Rules (Must Follow):');
      for (var rule in activeRules) {
        if (rule.isActive) {
           buffer.writeln('- \${rule.instructionText}');
        }
      }
    }

    if (activePatterns.isNotEmpty) {
      buffer.writeln('Observed Preferences (Suggested):');
      for (var pattern in activePatterns) {
        if (pattern.confidence > 0.3) {
           buffer.writeln('- \${pattern.ruleJson}');
        }
      }
    }
    buffer.writeln('---------------------------------------');
    return buffer.toString();
  }
}
