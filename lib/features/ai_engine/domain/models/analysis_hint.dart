class AnalysisHint {
  final String documentId;
  final String text; // The complex term or dense passage
  final int startIndex;
  final int endIndex;

  const AnalysisHint({
    required this.documentId,
    required this.text,
    required this.startIndex,
    required this.endIndex,
  });

  Map<String, dynamic> toMap() {
    return {
      'document_id': documentId,
      'text': text,
      'start_index': startIndex,
      'end_index': endIndex,
    };
  }

  factory AnalysisHint.fromMap(Map<String, dynamic> map) {
    return AnalysisHint(
      documentId: map['document_id'] as String,
      text: map['text'] as String,
      startIndex: map['start_index'] as int,
      endIndex: map['end_index'] as int,
    );
  }
}
