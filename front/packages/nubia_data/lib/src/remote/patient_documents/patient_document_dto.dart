import 'package:nubia_domain/src/entities/patient_document.dart';

class PatientDocumentDto {
  final String id;
  final String category;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String createdAt;

  const PatientDocumentDto({
    required this.id,
    required this.category,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory PatientDocumentDto.fromJson(Map<String, dynamic> json) =>
      PatientDocumentDto(
        id: json['id'] as String,
        category: json['category'] as String,
        filename: json['filename'] as String,
        mimeType: json['mime_type'] as String,
        sizeBytes: json['size_bytes'] as int,
        createdAt: json['created_at'] as String,
      );

  PatientDocument toDomain() => PatientDocument(
        id: id,
        category: category,
        filename: filename,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        createdAt: DateTime.parse(createdAt),
      );
}
