class LanguageExample {
  final String japanese;
  final String romaji;
  final String english;

  LanguageExample({
    required this.japanese,
    required this.romaji,
    required this.english,
  });

  factory LanguageExample.fromJson(Map<String, dynamic> json) {
    return LanguageExample(
      japanese: json['japanese'] as String? ?? json['text'] as String? ?? '',
      romaji: json['romaji'] as String? ?? '',
      english: json['english'] as String? ?? json['translation'] as String? ?? '',
    );
  }
}

class ContextualResponse {
  final String definition;
  final String explanation;
  final List<String> examples;
  
  // Language specific fields
  final bool isLanguageContent;
  final String? word;
  final String? romaji;
  final String? pronunciation;
  final String? pitchPattern;
  final String? meaning;
  final String? jlptLevel;
  final String? languageNotes;
  final List<LanguageExample> languageExamples;

  const ContextualResponse({
    required this.definition,
    required this.explanation,
    required this.examples,
    this.isLanguageContent = false,
    this.word,
    this.romaji,
    this.pronunciation,
    this.pitchPattern,
    this.meaning,
    this.jlptLevel,
    this.languageNotes,
    this.languageExamples = const [],
  });

  factory ContextualResponse.fromJson(Map<String, dynamic> json) {
    bool isLang = json['isLanguageContent'] as bool? ?? false;
    
    // Sometimes the LLM returns Japanese examples under "examples" if we are not explicitly mapping it,
    // so let's check for "languageExamples" or structured items in "examples".
    List<LanguageExample> parsedLangExamples = [];
    List<String> parsedExamples = [];

    if (json.containsKey('languageExamples') && json['languageExamples'] is List) {
       parsedLangExamples = (json['languageExamples'] as List).map((e) => LanguageExample.fromJson(e)).toList();
    } else if (json.containsKey('examples') && json['examples'] is List) {
       for (var e in json['examples']) {
         if (e is String) {
           parsedExamples.add(e);
         } else if (e is Map<String, dynamic>) {
           parsedLangExamples.add(LanguageExample.fromJson(e));
         }
       }
    }

    return ContextualResponse(
      definition: json['definition'] as String? ?? json['meaning'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      examples: parsedExamples,
      isLanguageContent: isLang || json.containsKey('romaji'),
      word: json['word'] as String?,
      romaji: json['romaji'] as String?,
      pronunciation: json['pronunciation'] as String?,
      pitchPattern: json['pitchPattern'] as String?,
      meaning: json['meaning'] as String?,
      jlptLevel: json['jlptLevel'] as String?,
      languageNotes: json['languageNotes'] as String?,
      languageExamples: parsedLangExamples,
    );
  }
}
