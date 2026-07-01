import '../../../memory/domain/models/memory_models.dart';

enum QueryMode {
  define,
  explain,
  languageBreakdown,
  custom,
}

class ContextualQuery {
  final String selectedText;
  final String surroundingContext;
  final String? languageHint;
  final QueryMode queryMode;
  final MemoryContext? memoryContext;

  const ContextualQuery({
    required this.selectedText,
    required this.surroundingContext,
    this.languageHint,
    required this.queryMode,
    this.memoryContext,
  });
}
