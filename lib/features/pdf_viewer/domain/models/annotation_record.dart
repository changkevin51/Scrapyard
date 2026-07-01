import 'dart:convert';

enum AnnotationType { highlight, ink, comment, shape }

class AnnotationRecord {
  final String id;
  final String documentId;
  final int pageNumber;
  final AnnotationType type;
  final Map<String, dynamic> data;

  AnnotationRecord({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.type,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'page_number': pageNumber,
      'type': type.name,
      'data': jsonEncode(data),
    };
  }

  factory AnnotationRecord.fromMap(Map<String, dynamic> map) {
    return AnnotationRecord(
      id: map['id'],
      documentId: map['document_id'],
      pageNumber: map['page_number'],
      type: AnnotationType.values.byName(map['type']),
      data: jsonDecode(map['data']),
    );
  }
}
